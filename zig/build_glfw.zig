const std = @import("std");

const srcs = [_][]const u8{
    "context.c",
    "init.c",
    "input.c",
    "monitor.c",
    "platform.c",
    "vulkan.c",
    "window.c",
    "egl_context.c",
    "osmesa_context.c",
    "null_init.c",
    "null_monitor.c",
    "null_window.c",
    "null_joystick.c",
};

const srcs_win32 = [_][]const u8{
    "win32_module.c",
    "win32_time.c",
    "win32_thread.c",

    "win32_init.c",
    "win32_joystick.c",
    "win32_monitor.c",
    "win32_window.c",
    "wgl_context.c",
};

const srcs_posix = [_][]const u8{
    "posix_module.c",
    "posix_time.c",
    "posix_thread.c",

    "linux_joystick.c",
    "posix_poll.c",
};

const srcs_wayland = [_][]const u8{
    "wl_init.c",
    "wl_monitor.c",
    "wl_window.c",
};

const flags_wayland = [_][]const u8{
    "-D_GLFW_WAYLAND",
};

const wayland_protocols = [_][]const u8{
    "wayland.xml",
    "viewporter.xml",
    "xdg-shell.xml",
    "idle-inhibit-unstable-v1.xml",
    "pointer-constraints-unstable-v1.xml",
    "relative-pointer-unstable-v1.xml",
    "fractional-scale-v1.xml",
    "xdg-activation-v1.xml",
    "xdg-decoration-unstable-v1.xml",
};

pub fn build(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    glfw_dep: *std.Build.Dependency,
) !*std.Build.Step.Compile {
    const t = b.addTranslateC(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = glfw_dep.path("include/GLFW/glfw3.h"),
    });
    t.addIncludePath(glfw_dep.path("deps"));
    t.defineCMacro("GLFW_INCLUDE_NONE", "1");

    const mod = t.createModule();

    const lib = b.addLibrary(.{
        .name = "glfw",
        .root_module = mod,
    });

    if (target.result.os.tag == .windows) {
        lib.addCSourceFiles(.{
            .root = glfw_dep.path("src"),
            .files = &(srcs ++ srcs_win32),
        });
    } else {
        // wayland
        lib.addCSourceFiles(.{
            .root = glfw_dep.path("src"),
            .files = &(srcs ++ srcs_posix ++ srcs_wayland),
            .flags = &flags_wayland,
        });

        const wayland_scanner = try b.findProgram(&.{"wayland-scanner"}, &.{});
        for (wayland_protocols) |xml_name| {
            const xml_path = glfw_dep.path("deps/wayland").path(b, xml_name);
            const stem = std.fs.path.stem(xml_name);

            {
                // client-header
                const run_wayland_scanner = b.addSystemCommand(&.{wayland_scanner});
                run_wayland_scanner.addArg("client-header");
                run_wayland_scanner.addFileArg(xml_path);
                const name = b.fmt("{s}-client-protocol.h", .{stem});
                const client_header = run_wayland_scanner.addOutputFileArg(name);
                lib.installHeader(client_header, name);
            }
            {
                // private-code
                const run_wayland_scanner = b.addSystemCommand(&.{wayland_scanner});
                run_wayland_scanner.addArg("private-code");
                run_wayland_scanner.addFileArg(xml_path);
                const name = b.fmt("{s}-client-protocol-code.h", .{stem});
                const client_header = run_wayland_scanner.addOutputFileArg(name);
                lib.installHeader(client_header, name);
            }
        }

        lib.addIncludePath(lib.getEmittedIncludeTree());
    }

    return lib;
}
