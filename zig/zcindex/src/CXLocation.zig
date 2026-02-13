const std = @import("std");
const c = @import("cindex");
const CXString = @import("CXString.zig");

pub const Location = struct {
    line: c_uint,
    column: c_uint,
    offset: c_uint,
};

start: Location,
end: Location,

pub fn init(cursor: c.CXCursor) @This() {
    var this: @This() = undefined;
    const extent = c.clang_getCursorExtent(cursor);
    const start = c.clang_getRangeStart(extent);
    c.clang_getExpansionLocation(start, null, &this.start.line, &this.start.column, &this.start.offset);
    const end = c.clang_getRangeEnd(extent);
    c.clang_getExpansionLocation(end, null, &this.end.line, &this.end.column, &this.end.offset);
    return this;
}

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
