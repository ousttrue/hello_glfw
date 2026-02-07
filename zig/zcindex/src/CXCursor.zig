const std = @import("std");
const c = @import("cindex");
const CXString = @import("CXString.zig");
const cx_declaration = @import("cx_declaration.zig");

parent: c.CXCursor,
cursor: c.CXCursor,
children: std.ArrayList(c.CXCursor) = .{},
display: c.CXString,
filename: c.CXString,

pub fn init(cursor: c.CXCursor, parent: c.CXCursor) @This() {
    var this = @This(){
        .parent = parent,
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

pub fn deinit(this: *@This()) void {
    c.clang_disposeString(this.display);
    c.clang_disposeString(this.filename);
    // this.children.deinit(allocator);
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

pub fn isFromMainFile(this: @This()) bool {
    const loc = c.clang_getCursorLocation(this.cursor);
    return c.clang_Location_isFromMainFile(loc) != 0;
}

pub fn getDisplay(this: @This()) []const u8 {
    if (c.clang_getCString(this.display)) |p| {
        return std.mem.span(p);
    } else {
        return "";
    }
}
