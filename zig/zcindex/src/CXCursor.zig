const std = @import("std");
const c = @import("cindex");
const cxcursor_kind = @import("cxcursor_kind.zig");
const cx_declaration = @import("cx_declaration.zig");

cursor: c.CXCursor,
spelling: c.CXString,
display: c.CXString,
filename: c.CXString,

pub fn init(cursor: c.CXCursor) @This() {
    var this = @This(){
        .cursor = cursor,
        .spelling = c.clang_getCursorSpelling(cursor),
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
    c.clang_disposeString(this.spelling);
    c.clang_disposeString(this.display);
    c.clang_disposeString(this.filename);
}

pub fn debugPrint(this: @This()) void {
    std.log.warn("[{s}] {s}", .{ this.getKindName(), this.getSpelling() });
}

pub fn isFromMainFile(this: @This()) bool {
    const loc = c.clang_getCursorLocation(this.cursor);
    return c.clang_Location_isFromMainFile(loc) != 0;
}

pub fn getSpelling(this: @This()) []const u8 {
    if (c.clang_getCString(this.spelling)) |p| {
        return std.mem.span(p);
    } else {
        return "";
    }
}

pub fn getDisplay(this: @This()) []const u8 {
    if (c.clang_getCString(this.display)) |p| {
        return std.mem.span(p);
    } else {
        return "";
    }
}

pub fn getKindName(this: @This()) []const u8 {
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
