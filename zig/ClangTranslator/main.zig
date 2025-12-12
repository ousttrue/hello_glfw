// https://rocm.docs.amd.com/projects/llvm-project/en/latest/LLVM/clang/html/LibClang.html

const std = @import("std");
const c = @import("clang");

pub fn main() void {
    const index = c.clang_createIndex(0, 0);

    const unit = c.clang_parseTranslationUnit(
        index,
        std.os.argv[1],
        null,
        0,
        null,
        0,
        c.CXTranslationUnit_None,
    ) orelse {
        @panic("clang_parseTranslationUnit");
    };
    defer c.clang_disposeTranslationUnit(unit);

    var data = Data.init();
    defer data.deinit();

    _ = c.clang_visitChildren(
        c.clang_getTranslationUnitCursor(unit),
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
    data.onVisit(cursor);

    return c.CXChildVisit_Recurse;
}

const Data = struct {
    fn init() @This() {
        return .{};
    }

    fn deinit(this: *@This()) void {
        _ = this;
    }

    fn onVisit(this: *@This(), cursor: c.CXCursor) void {
        _ = this;
        std.log.debug("{}", .{cursor.kind});
    }
};
