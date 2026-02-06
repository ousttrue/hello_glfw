// https://rocm.docs.amd.com/projects/llvm-project/en/latest/LLVM/clang/html/LibClang.html

const std = @import("std");
const c = @import("cindex");

const CIndexParser = @import("CIndexParsr.zig");
const ClientData = @import("ClientData.zig");
const CXCursor = @import("CXCursor.zig");
const zig_generator = @import("zig_generator.zig");
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

    for (data.cursors.items) |cursor| {
        if (try cx_declaration.Type.createFromCursor(allocator, cursor)) |decl| {
            defer decl.destroy(allocator);
            const zig_src = try zig_generator.allocPrintDecl(allocator, decl);
            defer allocator.free(zig_src);

            try writer.interface.print("{s}\n", .{zig_src});
            // const zig_src = try zig_generator.allocPrintDecl(allocator, decl);
            // defer allocator.free(zig_src);
            //
        }
    }
}

const T = struct {
    export fn debug_visitor(
        _cursor: c.CXCursor,
        _parent: c.CXCursor,
        client_data: c.CXClientData,
    ) c.CXChildVisitResult {
        _ = client_data;

        var cursor = CXCursor.init(_cursor);
        defer cursor.deinit();

        var parent = CXCursor.init(_parent);
        defer parent.deinit();

        const loc = cursor.getLocation();
        std.log.warn("{s}:{}:{} => {s}", .{ loc.path, loc.line, loc.col, cursor.getDisplay() });

        // if (c.clang_getCString(cursor.filename)) |p| {
        //     const cursor_path = std.mem.span(p);
        //     std.log.warn("=> {s}: {s}", .{ cursor_path, cursor.getDisplay() });
        // } else {
        //     std.log.warn("no file: {s}", .{cursor.getDisplay()});
        // }

        // std.log.warn("{s}", .{cursor.getDisplay()});
        return c.CXVisit_Continue;
    }
};

test {
    _ = cx_declaration;
    _ = zig_generator;
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
        ClientData.visitor,
        &data,
    );

    {
        const cursor = data.getCursorByName("__unknown__");
        try std.testing.expect(cursor == null);
    }
    {
        const cursor = data.getCursorByName("GetIO").?;
        if (try cx_declaration.Type.createFromCursor(allocator, cursor)) |decl| {
            defer decl.destroy(allocator);
            try std.testing.expect(@as(cx_declaration.Type, decl) == cx_declaration.Type.function);
            const f = decl.function;
            try std.testing.expectEqualSlices(u8, "GetIO", f.name);

            // try std.testing.expect(@as(cx_declaration.Type, decl) == cx_declaration.Type.function);

            //     const f = decl.function_decl;
            //     const ret_decl = f.getReturnDecl();
            //     try std.testing.expect(@as(cx_declaration.DeclarationType, ret_decl) ==
            //         cx_declaration.DeclarationType.pointer);

            const zig_src = try zig_generator.allocPrintDecl(allocator, decl);
            defer allocator.free(zig_src);
            try std.testing.expectEqualSlices(u8, "pub extern fn GetIO() [*c]ImGuiIO;", zig_src);
        }
    }
    // {
    //     const cursor = data.getCursorByName("ImGuiIO").?;
    //     const decl = cursor.getDeclaration();
    //     try std.testing.expect(decl == null);
    // }

    // const _zig_source = try out.toOwnedSlice();
    // defer allocator.free(_zig_source);
    // std.log.warn("{s}", .{_zig_source});
    // std.log.warn("hello", .{});

    // const zig_source = try allocator.dupeZ(u8, _zig_source);
    // defer allocator.free(zig_source);
    //
    // var tree = try std.zig.Ast.parse(allocator, zig_source, .zig);
    // defer tree.deinit(allocator);
    //
    // for (tree.rootDecls(), 0..) |root_decl_index, i| {
    //     std.log.debug("root decls[{}]: {s}", .{ i, tree.getNodeSource(root_decl_index) });
    // }
}
