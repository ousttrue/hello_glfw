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

pub fn initFromCursorSpelling(cursor: c.CXCursor) @This() {
    return init(c.clang_getCursorSpelling(cursor));
}

pub fn initFromTypeSpelling(cx_type: c.CXType) @This() {
    return init(c.clang_getTypeSpelling(cx_type));
}

pub fn initFromMangling(cursor: c.CXCursor) @This() {
    return init(c.clang_Cursor_getMangling(cursor));
}

pub fn initFromCursorFilepath(cursor: c.CXCursor) @This() {
    const loc = c.clang_getCursorLocation(cursor);
    var file: c.CXFile = undefined;
    c.clang_getFileLocation(loc, &file, null, null, null);
    return init(c.clang_File_tryGetRealPathName(file));
}

pub fn deinit(this: @This()) void {
    _ = this;
    // c.clang_disposeString(this.str);
}

pub fn toString(this: *const @This()) []const u8 {
    if (c.clang_getCString(this.str)) |str| {
        return std.mem.span(str);
    } else {
        return "";
    }
}
