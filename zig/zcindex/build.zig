const std = @import("std");

const name = "zcindex";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const llvm_dir = b.option([]const u8, "llvm", "llvm path. like /usr/lib/llvm/20") orelse "/usr";
    var llvm_include: []const u8 = b.fmt("{s}/include", .{llvm_dir});
    var llvm_lib: []const u8 = b.fmt("{s}/lib64", .{llvm_dir});
    var llvm_lib_name: []const u8 = "clang";
    if (target.result.os.tag == .windows) {
        llvm_include = "C:/Program Files/LLVM/include";
        llvm_lib = "C:/Program Files/LLVM/lib";
        llvm_lib_name = "libclang";
    }

    const t = b.addTranslateC(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .cwd_relative = b.fmt("{s}/clang-c/Index.h", .{llvm_include}) },
    });
    t.addIncludePath(.{ .cwd_relative = llvm_include });

    const mod = b.addModule(name, .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
        .imports = &.{
            .{
                .name = "cindex",
                .module = t.createModule(),
            },
        },
        .link_libc = true,
        .link_libcpp = true,
    });
    mod.linkSystemLibrary(llvm_lib_name, .{});
    mod.addLibraryPath(.{ .cwd_relative = llvm_lib });

    const exe = b.addExecutable(.{
        .name = name,
        .root_module = mod,
        .use_llvm = true,
    });
    b.installArtifact(exe);

    const test_exe = b.addTest(.{
        .name = "zcindex_test",
        .root_module = mod,
    });
    b.installArtifact(test_exe);

    const run_test = b.addRunArtifact(test_exe);
    b.step("test", "run zcindex_test").dependOn(&run_test.step);
}
