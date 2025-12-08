const std = @import("std");
const build_glfw = @import("build_glfw.zig");
const build_glad = @import("build_glad.zig");

const Sample = struct {
    name: []const u8,
    root_source_file: []const u8,
    use_sokol: bool = false,
};

const samples = [_]Sample{
    .{
        .name = "glfw_triangle",
        .root_source_file = "src/simple.zig",
    },
    .{
        .name = "sokol_glfw_triangle",
        .root_source_file = "src/sokol.zig",
        .use_sokol = true,
    },
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sokol_dep = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });

    for (samples) |sample| {
        try build_sample(b, target, optimize, sample, sokol_dep);
    }
}

fn build_sample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    sample: Sample,
    sokol_dep: *std.Build.Dependency,
) !void {
    const mod = b.addModule(sample.name, .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path(sample.root_source_file),
    });

    const exe = b.addExecutable(.{
        .name = sample.name,
        .root_module = mod,
    });
    b.installArtifact(exe);

    const glfw_dep = b.dependency("glfw", .{});

    const glfw_lib = try build_glfw.build(b, target, optimize, glfw_dep);
    exe.linkLibrary(glfw_lib);
    exe.root_module.addImport("glfw", glfw_lib.root_module);

    const glad_lib = try build_glad.build(b, target, optimize, glfw_dep);
    exe.linkLibrary(glad_lib);
    exe.root_module.addImport("glad", glad_lib.root_module);

    if (sample.use_sokol) {
        const t = b.addTranslateC(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/glfw_glue.h"),
        });
        t.addIncludePath(sokol_dep.path("src/sokol/c"));
        mod.addImport("glfw", t.createModule());

        exe.addCSourceFiles(.{
            .root = b.path("src"),
            .files = &.{"glfw_glue.c"},
        });
        exe.addIncludePath(sokol_dep.path("src/sokol/c"));

        mod.addImport("sokol", sokol_dep.module("sokol"));
    }
}
