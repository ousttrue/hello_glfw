// https://rocm.docs.amd.com/projects/llvm-project/en/latest/LLVM/clang/html/LibClang.html

const std = @import("std");
const c = @import("cindex");

const CIndexParser = @import("CIndexParsr.zig");
const ClientData = @import("ClientData.zig");
const CXCursor = @import("CXCursor.zig");
const ZigGenerator = @import("ZigGenerator.zig");
const cx_declaration = @import("cx_declaration.zig");
const DebugPrinter = @import("DebugPrinter.zig");
const SizePrinter = @import("SizePrinter.zig");

fn usage(writer: *std.Io.Writer) !void {
    try writer.print(
        \\ usage: {s} {{zig|debug|size_h|size_cpp}} c_headers....
        \\     ex. zcindex zig imgui.h
        \\
    , .{std.mem.span(std.os.argv[0])});
}

pub fn main() !void {
    var writer_buf: [1024]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&writer_buf);
    defer writer.interface.flush() catch @panic("OOM");

    if (std.os.argv.len >= 3) {
        const cmd: []const u8 = std.mem.span(std.os.argv[1]);
        if (std.mem.eql(u8, cmd, "zig")) {
            try main_zig(std.os.argv[2..], &writer.interface);
        } else if (std.mem.eql(u8, cmd, "debug")) {
            try main_debug(std.os.argv[2..], &writer.interface);
        } else if (std.mem.eql(u8, cmd, "size_h")) {
            // extern "C"
            try main_size(std.os.argv[2..], &writer.interface, false);
        } else if (std.mem.eql(u8, cmd, "size_cpp")) {
            // impl
            try main_size(std.os.argv[2..], &writer.interface, true);
        }
        return;
    }

    try usage(&writer.interface);
}

fn main_size(argv: []const [*:0]const u8, writer: *std.Io.Writer, impl: bool) !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.detectLeaks();
    const allocator = gpa.allocator();

    var cindex_parser = if (argv.len == 1)
        try CIndexParser.fromSingleHeader(allocator, argv[0])
    else
        try CIndexParser.fromMultiHeadr(allocator, argv);
    defer cindex_parser.deinit();

    const tu = try cindex_parser.parse();
    defer c.clang_disposeTranslationUnit(tu);

    var printer = SizePrinter.init(
        allocator,
        writer,
        cindex_parser.entry_point,
        cindex_parser.include_dirs.items,
        impl,
    );
    defer printer.deinit();

    _ = c.clang_visitChildren(
        c.clang_getTranslationUnitCursor(tu),
        SizePrinter.SizePrinter_visitor,
        &printer,
    );
}

fn main_debug(argv: []const [*:0]const u8, writer: *std.Io.Writer) !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.detectLeaks();
    const allocator = gpa.allocator();

    var cindex_parser = if (argv.len == 1)
        try CIndexParser.fromSingleHeader(allocator, argv[0])
    else
        try CIndexParser.fromMultiHeadr(allocator, argv);
    defer cindex_parser.deinit();

    const tu = try cindex_parser.parse();
    defer c.clang_disposeTranslationUnit(tu);

    var printer = DebugPrinter.init(
        writer,
        cindex_parser.entry_point,
        cindex_parser.include_dirs.items,
    );
    defer printer.deinit();

    _ = c.clang_visitChildren(
        c.clang_getTranslationUnitCursor(tu),
        DebugPrinter.DebugPrinter_visitor,
        &printer,
    );
}

fn main_zig(argv: []const [*:0]const u8, writer: *std.Io.Writer) !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.detectLeaks();
    const allocator = gpa.allocator();

    var cindex_parser = if (argv.len == 1)
        try CIndexParser.fromSingleHeader(allocator, argv[0])
    else
        try CIndexParser.fromMultiHeadr(allocator, argv);
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
        ClientData.ClientData_visitor,
        &data,
    );

    try writer.writeAll(
        \\const std = @import("std");
        \\
        \\pub const c = @cImport({
        \\    @cInclude("size_offset.h");
        \\});
        \\
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
                try writer.print("{s}\n", .{zig_src});
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
        ClientData.ClientData_visitor,
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
        ClientData.ClientData_visitor,
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
        ClientData.ClientData_visitor,
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
