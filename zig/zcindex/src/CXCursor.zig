const std = @import("std");
const c = @import("cindex");
const CXString = @import("CXString.zig");
const cx_declaration = @import("cx_declaration.zig");

parent: c.CXCursor,
cursor: c.CXCursor,
children: std.ArrayList(c.CXCursor) = .{},

pub fn init(cursor: c.CXCursor, parent: c.CXCursor) @This() {
    return .{
        .parent = parent,
        .cursor = cursor,
    };
}

pub fn debugPrint(this: @This()) void {
    const pp = c.clang_getCursorPrettyPrinted(this.cursor, null);
    defer c.clang_disposeString(pp);
    const ppp = c.clang_getCString(pp);
    const kind_name = CXString.initFromCursorKind(this.cursor);
    defer kind_name.deinit();
    const spelling = CXString.initFromCursorSpelling(this.cursor);
    defer spelling.deinit();
    std.log.warn("[{s}] {s} => {s}", .{ kind_name.toString(), spelling.toString(), std.mem.span(ppp) });
}

pub fn getDisplay(this: @This()) []const u8 {
    if (c.clang_getCString(this.display)) |p| {
        return std.mem.span(p);
    } else {
        return "";
    }
}
