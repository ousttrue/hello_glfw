// https://rocm.docs.amd.com/projects/llvm-project/en/latest/LLVM/clang/html/LibClang.html

const std = @import("std");
const c = @import("cindex");

const CIndexParser = @import("CIndexParsr.zig");
const ClientData = @import("ClientData.zig");
const CXCursor = @import("CXCursor.zig");
const ZigGenerator = @import("ZigGenerator.zig");
const cx_declaration = @import("cx_declaration.zig");

pub fn main() !void {
    if (std.os.argv.len < 2) {
        return error.no_commandline_arg;
    }

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.detectLeaks();
    const allocator = gpa.allocator();

    var writer_buf: [1024]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&writer_buf);
    defer writer.interface.flush() catch @panic("OOM");

    var cindex_parser = if (std.os.argv.len == 2)
        try CIndexParser.fromSingleHeader(allocator, std.os.argv[1])
    else
        try CIndexParser.fromMultiHeadr(allocator, std.os.argv[1..]);
    defer cindex_parser.deinit();

    const tu = try cindex_parser.parse();
    defer c.clang_disposeTranslationUnit(tu);

    var data = ClientData.init(
        allocator,
        cindex_parser.entry_point,
        cindex_parser.include_dirs.items,
    );
    defer data.deinit();

    _ = c.clang_visitChildren(
        c.clang_getTranslationUnitCursor(tu),
        ClientData.visitor,
        &data,
    );

    try writer.interface.writeAll(
        \\pub fn ImVector(T: type) type {
        \\    return struct {
        \\        Size: i32,
        \\        Capacity: i32,
        \\        Data: *T,
        \\    };
        \\}
        \\
        \\
    );

    var g = ZigGenerator.init(allocator);
    defer g.deinit();
    for (data.cursors.items) |cursor| {
        if (try cx_declaration.Type.createFromCursor(allocator, cursor)) |decl| {
            defer decl.destroy(allocator);
            const zig_src = try g.allocPrintDecl(allocator, decl);
            defer allocator.free(zig_src);
            if (zig_src.len > 0) {
                try writer.interface.print("{s}\n", .{zig_src});
            }
        }
    }
}

test {
    _ = cx_declaration;
    // _ = zig_generator;
    std.testing.refAllDecls(@This());
    // std.testing.refAllDeclsRecursive(@import("root"));
}

export fn debug_visitor(
    _cursor: c.CXCursor,
    _parent: c.CXCursor,
    client_data: c.CXClientData,
) c.CXChildVisitResult {
    _ = client_data;

    var cursor = CXCursor.init(_cursor, _parent);
    switch (cursor.cursor.kind) {
        c.CXCursor_MacroDefinition => {},
        else => {
            cursor.debugPrint();
        },
    }

    return c.CXChildVisit_Recurse;
}

// test "debug visitor" {
//     const allocator = std.testing.allocator;
//     const contents =
//         \\enum Hoge {
//         \\  HOGE_X = 1,
//         \\  HOGE_Y = 2,
//         \\};
//     ;
//     var cindex_parser = try CIndexParser.fromContents(allocator, contents);
//     defer cindex_parser.deinit();
//
//     const _tu = try cindex_parser.parse();
//     try std.testing.expect(_tu != null);
//     const tu = _tu orelse @panic("parse");
//     defer c.clang_disposeTranslationUnit(tu);
//
//     _ = c.clang_visitChildren(
//         c.clang_getTranslationUnitCursor(tu),
//         debug_visitor,
//         null,
//     );
// }

test "cindex" {
    const allocator = std.testing.allocator;
    const contents =
        \\struct ImGuiIO{
        \\  int ConfigFlags;
        \\};
        \\ImGuiIO& GetIO();
        \\
    ;
    var cindex_parser = try CIndexParser.fromContents(allocator, contents);
    defer cindex_parser.deinit();

    const _tu = try cindex_parser.parse();
    try std.testing.expect(_tu != null);
    const tu = _tu orelse @panic("parse");
    defer c.clang_disposeTranslationUnit(tu);

    var data = ClientData.init(
        allocator,
        cindex_parser.entry_point,
        cindex_parser.include_dirs.items,
    );
    defer data.deinit();

    _ = c.clang_visitChildren(
        c.clang_getTranslationUnitCursor(tu),
        // T.debug_visitor,
        ClientData.visitor,
        &data,
    );

    {
        const cursor = data.getCursorByName("__unknown__");
        try std.testing.expect(cursor == null);
    }
}

test "zig struct" {
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

    var data = ClientData.init(
        allocator,
        cindex_parser.entry_point,
        cindex_parser.include_dirs.items,
    );
    defer data.deinit();
    _ = c.clang_visitChildren(
        c.clang_getTranslationUnitCursor(tu),
        ClientData.visitor,
        &data,
    );

    const cursor = data.getCursorByName("Hoge").?;
    const decl = (try cx_declaration.Type.createFromCursor(allocator, cursor)).?;
    defer decl.destroy(allocator);

    var zig_generator = ZigGenerator.init(allocator);
    defer zig_generator.deinit();
    const zig_src = try zig_generator.allocPrintDecl(allocator, decl);
    defer allocator.free(zig_src);
    try std.testing.expectEqualSlices(u8,
        \\pub const Hoge = struct {
        \\    a: i32,
        \\};
        \\
    , zig_src);
}

// const ENUM = enum(c_int)
// {
//     A = 1,
//     B = 3,
// };
// const E = std.enums.EnumFieldStruct(ENUM, bool, false);
//
// test "EnumSet" {
//     const e = E{};
//
//     try std.testing.expectEqual(0, @as(u2, @bitCast(e.bits)));
// }

test "zig enum" {
    const allocator = std.testing.allocator;
    const contents =
        \\enum ImGuiWindowFlags_
        \\{
        \\    ImGuiWindowFlags_None                   = 0,
        \\};
    ;
    var cindex_parser = try CIndexParser.fromContents(allocator, contents);
    defer cindex_parser.deinit();

    const _tu = try cindex_parser.parse();
    try std.testing.expect(_tu != null);
    const tu = _tu orelse @panic("parse");
    defer c.clang_disposeTranslationUnit(tu);

    var data = ClientData.init(
        allocator,
        cindex_parser.entry_point,
        cindex_parser.include_dirs.items,
    );
    defer data.deinit();
    _ = c.clang_visitChildren(
        c.clang_getTranslationUnitCursor(tu),
        ClientData.visitor,
        &data,
    );

    const cursor = data.getCursorByName("ImGuiWindowFlags_").?;
    const decl = (try cx_declaration.Type.createFromCursor(allocator, cursor)).?;
    defer decl.destroy(allocator);

    var zig_generator = ZigGenerator.init(allocator);
    defer zig_generator.deinit();
    const zig_src = try zig_generator.allocPrintDecl(allocator, decl);
    defer allocator.free(zig_src);
    try std.testing.expectEqualSlices(u8,
        \\pub const ImGuiWindowFlags_ = enum(i32) {
        \\    ImGuiWindowFlags_None = 0,
        \\};
    , zig_src);
}
