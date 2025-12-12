// https://rocm.docs.amd.com/projects/llvm-project/en/latest/LLVM/clang/html/LibClang.html

const std = @import("std");
const c = @import("clang");

const DEFAULT_ARGS = [_][]const u8{
    "-x",
    "c++",
    // "-std=c++17",
    // "-target",
    // "x86_64-windows-msvc",
    // "-fdeclspec",
    // "-fms-compatibility-version=18",
    // "-fms-compatibility",
    // "-DNOMINMAX",
};

pub fn main() !void {
    if (std.os.argv.len < 2) {
        return error.no_commandline_arg;
    }

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.detectLeaks();
    const allocator = gpa.allocator();

    var command_line = std.ArrayList(*const u8){};
    defer command_line.deinit(allocator);

    for (DEFAULT_ARGS) |arg| {
        try command_line.append(allocator, &arg[0]);
    }
    // for (1..std.os.argv.len) |i| {
    //     try command_line.append(allocator, @ptrCast(&std.os.argv[i]));
    // }

    const index = c.clang_createIndex(0, 0);
    const flags =
        c.CXTranslationUnit_DetailedPreprocessingRecord | c.CXTranslationUnit_SkipFunctionBodies;

    var tu: c.CXTranslationUnit = undefined;
    const result = c.clang_parseTranslationUnit2(index,
        // entry point,
        std.os.argv[1],
        //command_line,
        &command_line.items[0], @intCast(command_line.items.len),
        // unsaved_files,
        null, 0,
        //
        flags, &tu);
    switch (result) {
        c.CXError_Success => {}, // SUCCESS
        c.CXError_Failure => @panic("failer"),
        c.CXError_Crashed => @panic("crash"),
        c.CXError_InvalidArguments => @panic("invalid arguments"),
        c.CXError_ASTReadError => @panic("AST read error"),
        else => @panic("unknown"),
    }
    defer c.clang_disposeTranslationUnit(tu);

    var data = Data.init();
    defer data.deinit();

    _ = c.clang_visitChildren(
        c.clang_getTranslationUnitCursor(tu),
        Visitor,
        &data,
    );
}

export fn Visitor(
    cursor: c.CXCursor,
    parent: c.CXCursor,
    client_data: c.CXClientData,
) c.CXChildVisitResult {
    _ = parent;

    const data: *Data = @ptrCast(client_data);
    if (data.onVisit(cursor)) {
        return c.CXChildVisit_Recurse;
    } else {
        return c.CXChildVisit_Break;
    }
}

const Data = struct {
    fn init() @This() {
        return .{};
    }

    fn deinit(this: *@This()) void {
        _ = this;
    }

    fn onVisit(this: *@This(), cursor: c.CXCursor) bool {
        _ = this;

        // std.log.debug("{}", .{cursor.kind});
        switch (cursor.kind) {
            c.CXCursor_FunctionDecl => {
                // https://clang.llvm.org/doxygen/group__CINDEX__STRING.html
                // const name = c.clang_getCursorDisplayName(cursor);
                // defer c.clang_disposeString(name);
                // std.log.debug("c.CXCursor_FunctionDecl => {s}", .{c.clang_getCString(name)});

                //
                const loc = c.clang_getCursorLocation(cursor);
                var file: c.CXFile = undefined;
                var line: u32 = undefined;
                var col: u32 = undefined;
                var offset: u32 = undefined;
                c.clang_getFileLocation(loc, &file, &line, &col, &offset);

                const filename = c.clang_File_tryGetRealPathName(file);
                defer c.clang_disposeString(filename);

                const filename_str = c.clang_getCString(filename);
                if (std.mem.startsWith(u8, std.mem.span(filename_str), "/usr")) {
                    std.log.warn("c.CXCursor_FunctionDecl => {s}:{}:{} break", .{
                        filename_str,
                        line,
                        col,
                        // offset,
                    });
                    return false;
                }
                std.log.debug("c.CXCursor_FunctionDecl => {s}:{}:{}", .{
                    filename_str,
                    line,
                    col,
                    // offset,
                });

                return true;
            },
            else => {
                std.log.err("unknown kind: {}", .{cursor.kind});
                return false;
            },
        }
    }
};
