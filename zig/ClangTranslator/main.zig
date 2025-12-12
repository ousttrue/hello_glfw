// https://rocm.docs.amd.com/projects/llvm-project/en/latest/LLVM/clang/html/LibClang.html

const std = @import("std");
const c = @import("clang");
const cxcursor_kind = @import("cxcursor_kind.zig");

const DEFAULT_ARGS = [_][]const u8{
    "-x",
    "c++",
    "-std=c++17",
};

const MSVC_ARGS = [_][]const u8{
    "-target",
    "x86_64-windows-msvc",
    "-fdeclspec",
    "-fms-compatibility-version=18",
    "-fms-compatibility",
    "-DNOMINMAX",
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

    const index = c.clang_createIndex(0, 0);
    const flags =
        c.CXTranslationUnit_DetailedPreprocessingRecord | c.CXTranslationUnit_SkipFunctionBodies;

    var entry_point_buf: [1024]u8 = undefined;
    const entry_point = try std.fs.cwd().realpathZ(std.os.argv[1], &entry_point_buf);
    entry_point_buf[entry_point.len] = 0;

    std.log.debug("entry_point => {s}", .{entry_point});

    var tu: c.CXTranslationUnit = undefined;
    const result = c.clang_parseTranslationUnit2(index,
        // entry point,
        &entry_point[0],
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

    var data = Data.init(entry_point);
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

    const data: *Data = @ptrCast(@alignCast(client_data));
    return data.onVisit(cursor);
}

const Data = struct {
    entry_point: []const u8,
    i: u32 = 0,

    fn init(entry_point: []const u8) @This() {
        return .{
            .entry_point = entry_point,
        };
    }

    fn deinit(this: *@This()) void {
        _ = this;
    }

    fn onVisit(this: *@This(), _cursor: c.CXCursor) c.CXChildVisitResult {
        var cursor = CXCursor.init(_cursor);
        defer cursor.deinit();

        const loc = cursor.getLocation();
        if (!std.mem.eql(u8, loc.path, this.entry_point)) {
            return c.CXVisit_Continue;
        }

        std.log.debug("[{:03}] {s}:{}:{} => <{s}> {s}", .{
            this.i,
            std.fs.path.basename(loc.path),
            loc.line,
            loc.col,
            cursor.kindName(),
            cursor.getDisplay(),
        });
        this.i += 1;
        return c.CXChildVisit_Continue;
    }
};

const CXCursor = struct {
    cursor: c.CXCursor,
    display: c.CXString,
    filename: c.CXString,

    fn init(cursor: c.CXCursor) @This() {
        var this = @This(){
            .cursor = cursor,
            .display = c.clang_getCursorDisplayName(cursor),
            .filename = undefined,
        };

        const loc = c.clang_getCursorLocation(cursor);
        var file: c.CXFile = undefined;
        c.clang_getFileLocation(loc, &file, null, null, null);
        this.filename = c.clang_File_tryGetRealPathName(file);
        return this;
    }

    fn deinit(this: *@This()) void {
        defer c.clang_disposeString(this.display);
        defer c.clang_disposeString(this.filename);
    }

    fn getDisplay(this: @This()) []const u8 {
        if (c.clang_getCString(this.display)) |p| {
            return std.mem.span(p);
        } else {
            return "";
        }
    }

    fn kindName(this: @This()) []const u8 {
        if (cxcursor_kind.toName(this.cursor.kind)) |str| {
            const prefix = "CXCursor_";
            if (std.mem.startsWith(u8, str, prefix)) {
                return str[prefix.len..];
            } else {
                return str;
            }
        } else {
            std.log.err("__UNKNOWN__ cursor kind: {}", .{this.cursor.kind});
            return "__UNKNOWN__";
        }
    }

    fn getLocation(this: @This()) struct {
        path: []const u8,
        line: u32,
        col: u32,
    } {
        const loc = c.clang_getCursorLocation(this.cursor);
        var line: u32 = undefined;
        var col: u32 = undefined;
        c.clang_getFileLocation(loc, null, &line, &col, null);

        if (c.clang_getCString(this.filename)) |p| {
            return .{
                .path = std.mem.span(p),
                .line = line,
                .col = col,
            };
        } else {
            return .{
                .path = "",
                .line = 0,
                .col = 0,
            };
        }
    }
};
