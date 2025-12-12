const std = @import("std");
const build_glfw = @import("build_glfw.zig");
const build_glad = @import("build_glad.zig");

const Sample = struct {
    name: []const u8,
    root_source_file: []const u8,
    use_sokol: bool = false,
    use_imgui: bool = false,
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
    .{
        .name = "glfw_imgui",
        .root_source_file = "src/imgui.zig",
        .use_imgui = true,
    },
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sokol_dep = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });

    const imgui_dep = b.dependency("imgui", .{
        .target = target,
        .optimize = optimize,
    });

    for (samples) |sample| {
        try build_sample(b, target, optimize, sample, sokol_dep, imgui_dep);
    }

    const cltgen = build_ClangTranslator(b, target, optimize);
    b.installArtifact(cltgen);
}

pub fn build_ClangTranslator(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const t = b.addTranslateC(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .cwd_relative = "/usr/lib/llvm/20/include/clang-c/Index.h" },
        .use_clang = true,
    });
    t.addIncludePath(.{ .cwd_relative = "/usr/lib/llvm/20/include" });

    const name = "cltgen";
    const mod = b.addModule(name, .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("ClangTranslator/main.zig"),
        .imports = &.{
            .{
                .name = "clang",
                .module = t.createModule(),
            },
        },
        .link_libc = true,
        .link_libcpp = true,
    });
    mod.linkSystemLibrary("clang", .{});
    mod.addLibraryPath(.{ .cwd_relative = "/usr/lib/llvm/20/lib64" });

    const exe = b.addExecutable(.{
        .name = name,
        .root_module = mod,
    });
    return exe;
}

fn build_sample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    sample: Sample,
    sokol_dep: *std.Build.Dependency,
    imgui_dep: *std.Build.Dependency,
) !void {
    const mod = b.addModule(sample.name, .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path(sample.root_source_file),
        .link_libc = true,
        .link_libcpp = true,
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

    if (sample.use_imgui) {
        exe.addCSourceFiles(.{
            .root = imgui_dep.path(""),
            .files = &.{
                "imgui.cpp",
                "imgui_demo.cpp",
                "imgui_draw.cpp",
                "imgui_tables.cpp",
                "imgui_widgets.cpp",
            },
            .flags = &.{},
        });
        exe.linkSystemLibrary("X11");

        //
        exe.addIncludePath(imgui_dep.path(""));
        exe.addCSourceFiles(.{
            .files = &.{
                "imgui_helper/imgui_without_mangling.cpp",
                "imgui_helper/imgui_impl_glfw.cpp",
                "imgui_helper/imgui_impl_opengl3.cpp",
            },
        });
    }
}
