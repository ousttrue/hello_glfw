const std = @import("std");
const build_glfw = @import("build_glfw.zig");
const build_glad = @import("build_glad.zig");
const name = "hello_glfw_zig";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule(name, .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });

    const exe = b.addExecutable(.{
        .name = name,
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
}
