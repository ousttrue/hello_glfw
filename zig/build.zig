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
    // .{
    //     .name = "glfw_triangle",
    //     .root_source_file = "src/simple.zig",
    // },
    // .{
    //     .name = "sokol_glfw_triangle",
    //     .root_source_file = "src/sokol.zig",
    //     .use_sokol = true,
    // },
    // .{
    //     .name = "glfw_imgui",
    //     .root_source_file = "src/imgui.zig",
    //     .use_imgui = true,
    // },
    .{
        .name = "glfw_imgui_clang",
        .root_source_file = "src/imgui_zcindex.zig",
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

    const zcindex_dep = b.dependency("zcindex", .{
        .target = b.graph.host,
        .optimize = std.builtin.OptimizeMode.ReleaseSafe,
    });

    const zcindex_run = b.addRunArtifact(zcindex_dep.artifact("zcindex"));
    zcindex_run.addFileArg(imgui_dep.path("imgui.h"));
    zcindex_run.addFileArg(imgui_dep.path("backends/imgui_impl_glfw.h"));
    zcindex_run.addFileArg(imgui_dep.path("backends/imgui_impl_opengl3.h"));
    const imgui_mod_src = zcindex_run.captureStdOut();
    const imgui_src_install = b.addInstallFile(imgui_mod_src, "src/imgui.zig");
    b.getInstallStep().dependOn(&imgui_src_install.step);
    const imgui_mod = b.addModule("imgui", .{
        .target = target,
        .optimize = optimize,
        // .root_source_file = imgui_mod_src,
        .root_source_file = b.path("zig-out/src/imgui.zig"),
    });

    // if (b.option(bool, "samples", "samples") orelse false) {
    for (samples) |sample| {
        const sample_compiled = try build_sample(b, target, optimize, sample, sokol_dep, imgui_dep);
        // if (sample.use_imgui) {
        sample_compiled.root_module.addImport("imgui", imgui_mod);
        sample_compiled.step.dependOn(&imgui_src_install.step);
        // }
    }
    // }
}

fn build_sample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    sample: Sample,
    sokol_dep: *std.Build.Dependency,
    imgui_dep: *std.Build.Dependency,
) !*std.Build.Step.Compile {
    _ = sokol_dep;
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

    // if (sample.use_sokol) {
    //     const t = b.addTranslateC(.{
    //         .target = target,
    //         .optimize = optimize,
    //         .root_source_file = b.path("src/glfw_glue.h"),
    //     });
    //     t.addIncludePath(sokol_dep.path("src/sokol/c"));
    //     mod.addImport("glfw", t.createModule());
    //
    //     exe.addCSourceFiles(.{
    //         .root = b.path("src"),
    //         .files = &.{"glfw_glue.c"},
    //     });
    //     exe.addIncludePath(sokol_dep.path("src/sokol/c"));
    //
    //     mod.addImport("sokol", sokol_dep.module("sokol"));
    // }

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
        // exe.linkSystemLibrary("X11");

        //
        // exe.addIncludePath(imgui_dep.path(""));
        // exe.addCSourceFiles(.{
        //     .files = &.{
        //         "imgui_helper/imgui_without_mangling.cpp",
        //         "imgui_helper/imgui_impl_glfw.cpp",
        //         "imgui_helper/imgui_impl_opengl3.cpp",
        //     },
        // });
    }

    return exe;
}
