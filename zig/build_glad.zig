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
    const lib = b.addLibrary(.{
        .name = "glad",
        .root_module = t.createModule(),
    });

    // glad
    lib.addCSourceFile(.{
        .file = b.path("src/glad_impl.c"),
    });
    lib.addIncludePath(glfw_dep.path("deps"));

    return lib;
}
