const std = @import("std");
const c = @import("cindex");
const CIndexParser = @import("CIndexParsr.zig");
const GetChildren = @This();
const CXString = @import("CXString.zig");

buf: []c.CXCursor,
index: usize,

pub fn isFromMainFile(cursor: c.CXCursor) bool {
    const loc = c.clang_getCursorLocation(cursor);
    return c.clang_Location_isFromMainFile(loc) != 0;
}

pub fn isAcceptable(
    cursor: c.CXCursor,
    entry_point: []const u8,
    include_dirs: []const []const u8,
) bool {
    if (isFromMainFile(cursor)) {
        return true;
    }

    const filename = CXString.initFromCursorFilepath(cursor);
    defer filename.deinit();

    // if (c.clang_getCString(cursor.filename)) |p| {
    {
        const cursor_path = filename.toString();
        // std.log.debug("{s}, {s}", .{ this.entry_point, cursor_path });
        if (std.mem.eql(u8, cursor_path, entry_point)) {
            return true;
        }
        for (include_dirs) |include| {
            if (std.mem.startsWith(u8, cursor_path, include)) {
                return true;
            }
        }
    }

    return false;
}
pub export fn GetChildren_visitor(
    cursor: c.CXCursor,
    parent: c.CXCursor,
    client_data: c.CXClientData,
) c.CXChildVisitResult {
    _ = parent;
    const this: *@This() = @ptrCast(@alignCast(client_data));
    this.buf[this.index] = cursor;
    this.index += 1;
    return c.CXChildVisit_Continue;
}

pub fn getChildren(cursor: c.CXCursor, buf: []c.CXCursor) ![]c.CXCursor {
    var this = @This(){
        .buf = buf,
        .index = 0,
    };

    _ = c.clang_visitChildren(
        cursor,
        GetChildren_visitor,
        &this,
    );

    return this.buf[0..this.index];
}

test "GetChildren_visitor" {
    const allocator = std.testing.allocator;
    const contents =
        \\struct Hoge{
        \\  int a;
        \\};
        \\
    ;
    var cindex_parser = try CIndexParser.fromContents(allocator, contents);
    defer cindex_parser.deinit();

    const _tu = try cindex_parser.parse();
    try std.testing.expect(_tu != null);
    const tu = _tu orelse @panic("parse");
    defer c.clang_disposeTranslationUnit(tu);

    var buf: [10000]c.CXCursor = undefined;
    const children = try getChildren(c.clang_getTranslationUnitCursor(tu), &buf);

    for (children) |child| {
        const spelling = CXString.initFromCursorSpelling(child);
        defer spelling.deinit();
        if (std.mem.eql(u8, spelling.toString(), "Hoge")) {
            var field_buf: [2]c.CXCursor = undefined;
            const fields = try getChildren(child, &field_buf);
            try std.testing.expectEqual(1, fields.len);
            const field_spelling = CXString.initFromCursorSpelling(fields[0]);
            defer field_spelling.deinit();
            try std.testing.expectEqualSlices(u8, field_spelling.toString(), "a");
            break;
        }
    }
}
