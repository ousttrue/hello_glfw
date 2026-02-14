const std = @import("std");
const c = @import("cindex");
const CXCursor = @import("CXCursor.zig");
const CXString = @import("CXString.zig");
const CXLocation = @import("CXLocation.zig");
const cx_declaration = @import("cx_declaration.zig");
const cx_util = @import("cx_util.zig");
const MAX_CHILDREN_LEN = 512;

writer: *std.Io.Writer,
allocator: std.mem.Allocator,
entry_point: []const u8,
include_dirs: []const []const u8,
stack: [128]c.CXCursor = undefined,
stack_index: usize = 0,
source_map: std.StringHashMap([]const u8),

pub fn init(
    writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
    entry_point: []const u8,
    include_dirs: []const []const u8,
) @This() {
    return .{
        .writer = writer,
        .allocator = allocator,
        .entry_point = entry_point,
        .include_dirs = include_dirs,
        .source_map = .init(allocator),
    };
}

pub fn deinit(this: *@This()) void {
    var it = this.source_map.iterator();
    while (it.next()) |p| {
        this.allocator.free(p.value_ptr.*);
    }
    this.source_map.deinit();
}

pub export fn DebugPrinter_visitor(
    cursor: c.CXCursor,
    parent: c.CXCursor,
    client_data: c.CXClientData,
) c.CXChildVisitResult {
    const data: *@This() = @ptrCast(@alignCast(client_data));
    return data.onVisit(cursor, parent) catch {
        return c.CXChildVisit_Break;
    };
}

fn onVisit(
    this: *@This(),
    _cursor: c.CXCursor,
    _parent: c.CXCursor,
) !c.CXChildVisitResult {
    if (!CXLocation.isAcceptable(_cursor, this.entry_point, this.include_dirs)) {
        // skip
        return c.CXVisit_Continue;
    }

    this.stack_index = 0;
    for (this.stack, 0..) |stack_cursor, i| {
        if (c.clang_equalCursors(stack_cursor, _parent) != 0) {
            this.stack_index = i + 1;
            break;
        }
    }

    this.stack[this.stack_index] = _cursor;

    const pp = CXString.initFromPP(_cursor);
    defer pp.deinit();
    const spelling = CXString.initFromCursorSpelling(_cursor);
    defer spelling.deinit();
    const kind = CXString.initFromCursorKind(_cursor);
    defer kind.deinit();

    return switch (_cursor.kind) {
        // c.CXCursor_StructDecl,
        c.CXCursor_FieldDecl,
        c.CXCursor_UnexposedExpr,
        c.CXCursor_TypedefDecl,
        c.CXCursor_EnumDecl,
        c.CXCursor_EnumConstantDecl,
        c.CXCursor_CXXMethod,
        c.CXCursor_Constructor,
        c.CXCursor_Destructor,
        c.CXCursor_ConversionFunction,
        c.CXCursor_ClassTemplate,
        => blk: {
            // not enter
            // try this.writer.print("[{s}] {s}\n", .{
            //     kind.toString(),
            //     pp.toString(),
            // });
            break :blk c.CXChildVisit_Continue;
        },

        c.CXCursor_MemberRef,
        c.CXCursor_MacroDefinition,
        c.CXCursor_MacroExpansion,
        c.CXCursor_InclusionDirective,
        c.CXCursor_TypeRef,
        c.CXCursor_DeclRefExpr,
        c.CXCursor_TemplateRef,
        c.CXCursor_ParenExpr,
        c.CXCursor_CallExpr,
        c.CXCursor_CStyleCastExpr,
        c.CXCursor_CompoundStmt,
        c.CXCursor_IntegerLiteral,
        c.CXCursor_FloatingLiteral,
        c.CXCursor_StringLiteral,
        c.CXCursor_CXXBoolLiteralExpr,
        c.CXCursor_Namespace,
        c.CXCursor_VarDecl,
        c.CXCursor_UnexposedAttr,
        c.CXCursor_TemplateTypeParameter,
        c.CXCursor_FunctionTemplate,
        c.CXCursor_UnaryExpr,
        c.CXCursor_UnaryOperator,
        c.CXCursor_BinaryOperator,
        => blk: {
            // try this.writeIndent();
            // try this.writer.print("[{s}] {s}\n", .{
            //     kind.toString(),
            //     pp.toString(),
            // });
            break :blk c.CXChildVisit_Continue;
        },

        c.CXCursor_StructDecl => blk: {
            // clang_Type_getSizeOf not support template class
            try this.writeIndent();

            var buf: [MAX_CHILDREN_LEN]c.CXCursor = undefined;
            const children = try cx_util.getChildren(_cursor, &buf);
            const fields = try cx_declaration.ContainerType.getFields(this.allocator, children);
            for(fields)|field|{
                field.type_ref.destroy(this.allocator);
            }
            defer this.allocator.free(fields);

            try this.writer.print("[{s}] {s} ({}) {}bytes\n", .{
                kind.toString(),
                spelling.toString(),
                fields.len,
                c.clang_Type_getSizeOf(c.clang_getCursorType(_cursor)),
            });

            break :blk c.CXChildVisit_Continue;
        },

        // c.CXCursor_FieldDecl => {
        //     // clang_Type_getSizeOf not support template class
        //     // clang_Cursor_getOffsetOfField not support template class field
        //     try this.writeIndent();
        //     try this.writer.print("[{s}] {}bit {}bytes {s} \n", .{
        //         kind.toString(),
        //         c.clang_Cursor_getOffsetOfField(_cursor),
        //         c.clang_Type_getSizeOf(c.clang_getCursorType(_cursor)),
        //         display.toString(),
        //     });
        // },
        c.CXCursor_FunctionDecl => blk: {
            // try this.writer.print("[{s}] {s}\n", .{
            //     kind.toString(),
            //     spelling.toString(),
            // });
            // const argc: usize = @intCast(c.clang_Cursor_getNumArguments(_cursor));
            // for (0..argc) |i| {
            //     const param = c.clang_Cursor_getArgument(_cursor, @intCast(i));
            //     try this.print_param(param);
            // }
            break :blk c.CXChildVisit_Continue;
        },
        // c.CXCursor_ParmDecl => blk: {
        //     // const cx_type = c.clang_get();
        //     try this.print_param(_cursor);
        //     break :blk c.CXChildVisit_Continue;
        // },
        else => blk: {
            // indent
            try this.writeIndent();
            try this.writer.print("[{s}] {s}\n", .{ kind.toString(), spelling.toString() });
            break :blk c.CXChildVisit_Continue;
        },
    };
}

fn print_param(this: *@This(), _cursor: c.CXCursor) !void {
    const pp = CXString.initFromPP(_cursor);
    defer pp.deinit();
    const spelling = CXString.initFromCursorSpelling(_cursor);
    defer spelling.deinit();
    const kind = CXString.initFromCursorKind(_cursor);
    defer kind.deinit();

    try this.writeIndent();
    try this.writer.print("[{s}] {s}\n", .{
        kind.toString(),
        pp.toString(),
    });
    var buf: [32]c.CXCursor = undefined;
    const children = try cx_util.getChildren(_cursor, &buf);
    for (children) |child| {
        const child_kind = CXString.initFromCursorKind(child);
        defer child_kind.deinit();
        const child_pp = CXString.initFromCursorDisplayName(child);
        defer child_pp.deinit();
        const src = try this.getSource(child);
        switch (child.kind) {
            c.CXCursor_TypeRef,
            c.CXCursor_ParmDecl,
            => {
                // skip
            },
            else => {
                try this.writeIndent();

                // const cursor_location = CXLocation.init(_cursor);
                const child_location = CXLocation.init(child);
                // CXLocation.init(_cursor).end.offset;
                // search next ')'
                var x = child_location.end.offset;
                while (x < src.len) : (x += 1) {
                    if (src[x] == ')' or src[x] == ',') {
                        break;
                    }
                }
                try this.writer.print("  [{s}] => '{s}'\n", .{
                    child_kind.toString(),
                    src[child_location.start.offset..x],
                });
            },
        }
    }
}
fn writeIndent(this: @This()) !void {
    for (0..this.stack_index) |_| {
        try this.writer.writeAll("  ");
    }
}

fn getSource(this: *@This(), cursor: c.CXCursor) ![]const u8 {
    const file = CXString.initFromCursorFilepath(cursor);
    defer file.deinit();
    const path = file.toString();
    if (this.source_map.get(path)) |src| {
        return src;
    } else {
        const src = try std.fs.cwd().readFileAllocOptions(
            this.allocator,
            path,
            std.math.maxInt(u32),
            null,
            .@"1",
            null,
        );
        try this.source_map.put(path, src);
        return src;
    }
}
