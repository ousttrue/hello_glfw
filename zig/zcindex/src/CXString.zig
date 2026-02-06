const std = @import("std");
const c = @import("cindex");

str: c.CXString,

pub fn init(str: c.CXString) @This() {
    return .{ .str = str };
}

pub fn initFromCursorKind(cursor: c.CXCursor) @This() {
    return init(c.clang_getCursorKindSpelling(cursor.kind));
}

pub fn initFromTypeKind(cx_type: c.CXType) @This() {
    return init(c.clang_getTypeKindSpelling(cx_type.kind));
}

pub fn deinit(this: @This()) void {
    c.clang_disposeString(this.str);
}

pub fn toString(this: @This()) []const u8 {
    if (c.clang_getCString(this.str)) |str| {
        return std.mem.span(str);
    } else {
        return "";
    }
}
