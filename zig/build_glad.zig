const std = @import("std");

pub fn build(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    glfw_dep: *std.Build.Dependency,
) !*std.Build.Step.Compile {
    const t = b.addTranslateC(.{
        .root_source_file = glfw_dep.path("deps/glad/gl.h"),
        .target = target,
        .optimize = optimize,
    });
    const mod = t.createModule();
    const lib = b.addLibrary(.{
        .name = "glad",
        .root_module = mod,
    });

    // glad
    mod.addCSourceFile(.{
        .file = b.path("src/glad_impl.c"),
    });
    mod.addIncludePath(glfw_dep.path("deps"));

    return lib;
}
