const std = @import("std");
const c = @import("cindex");
const CXCursor = @import("CXCursor.zig");
const CXString = @import("CXString.zig");
const cx_util = @import("cx_util.zig");

writer: *std.Io.Writer,
entry_point: []const u8,
include_dirs: []const []const u8,
stack: [128]c.CXCursor = undefined,
stack_index: usize = 0,

pub fn init(
    writer: *std.Io.Writer,
    entry_point: []const u8,
    include_dirs: []const []const u8,
) @This() {
    return .{
        .writer = writer,
        .entry_point = entry_point,
        .include_dirs = include_dirs,
    };
}

pub fn deinit(this: *@This()) void {
    _ = this;
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
    if (!cx_util.isAcceptable(_cursor, this.entry_point, this.include_dirs)) {
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

    const display = CXString.initFromCursorDisplayName(_cursor);
    defer display.deinit();
    const spelling = CXString.initFromCursorSpelling(_cursor);
    defer spelling.deinit();
    const kind = CXString.initFromCursorKind(_cursor);
    defer kind.deinit();

    switch (_cursor.kind) {
        c.CXCursor_UnexposedExpr,
        c.CXCursor_FunctionDecl,
        c.CXCursor_ParmDecl,
        c.CXCursor_TypedefDecl,
        c.CXCursor_EnumDecl,
        c.CXCursor_EnumConstantDecl,
        c.CXCursor_CXXMethod,
        c.CXCursor_ConversionFunction,
        c.CXCursor_MemberRef,
        c.CXCursor_Constructor,
        c.CXCursor_Destructor,
        c.CXCursor_MacroDefinition,
        c.CXCursor_MacroExpansion,
        c.CXCursor_InclusionDirective,
        c.CXCursor_TypeRef,
        c.CXCursor_DeclRefExpr,
        c.CXCursor_TemplateRef,
        c.CXCursor_UnaryOperator,
        c.CXCursor_BinaryOperator,
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
        => {
            // skip
        },
        c.CXCursor_StructDecl => {
            // clang_Type_getSizeOf not support template class
            try this.writeIndent();
            try this.writer.print("[{s}] {s} {}bytes\n", .{
                kind.toString(),
                spelling.toString(),
                c.clang_Type_getSizeOf(c.clang_getCursorType(_cursor)),
            });
        },
        c.CXCursor_FieldDecl => {
            // clang_Type_getSizeOf not support template class
            // clang_Cursor_getOffsetOfField not support template class field
            try this.writeIndent();
            try this.writer.print("[{s}] {}bit {}bytes {s} \n", .{
                kind.toString(),
                c.clang_Cursor_getOffsetOfField(_cursor),
                c.clang_Type_getSizeOf(c.clang_getCursorType(_cursor)),
                display.toString(),
            });
        },
        else => {
            // indent
            try this.writeIndent();
            try this.writer.print("[{s}] {s}\n", .{ kind.toString(), spelling.toString() });
        },
    }

    // return switch (cursor.cursor.kind) {
    //     c.CXCursor_Namespace => c.CXChildVisit_Recurse,
    //     c.CXCursor_StructDecl => c.CXChildVisit_Recurse,
    //     c.CXCursor_EnumDecl => c.CXChildVisit_Recurse,
    //     else => c.CXChildVisit_Continue,
    // };
    return c.CXChildVisit_Recurse;
}

fn writeIndent(this: @This()) !void {
    for (0..this.stack_index) |_| {
        try this.writer.writeAll("  ");
    }
}
