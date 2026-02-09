const std = @import("std");
const c = @import("cindex");
const CXCursor = @import("CXCursor.zig");
const CXString = @import("CXString.zig");

const skip_types = [_][]const u8{
    // template ImVector
    "ImVector",
    // ImGuiTextFilter::ImGuiTextRange
    "ImGuiTextRange",
};

writer: *std.Io.Writer,
entry_point: []const u8,
include_dirs: []const []const u8,
impl: bool,

stack: [128]c.CXCursor = undefined,
stack_index: usize = 0,

used: std.StringHashMap(u32),

pub fn init(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    entry_point: []const u8,
    include_dirs: []const []const u8,
    impl: bool,
) @This() {
    if (impl) {
        writer.writeAll(
            \\#include "imgui.h"
            \\
        ) catch @panic("OOM");
    }
    writer.writeAll(
        \\#include <stddef.h>
        \\
        \\#ifdef __cplusplus
        \\extern "C" {
        \\#endif
        \\
    ) catch @panic("OOM");

    return .{
        .writer = writer,
        .entry_point = entry_point,
        .include_dirs = include_dirs,
        .impl = impl,
        .used = .init(allocator),
    };
}

pub fn deinit(this: *@This()) void {
    this.used.deinit();
    this.writer.writeAll(
        \\#ifdef __cplusplus
        \\}
        \\#endif
        \\
    ) catch @panic("OOM");
}

pub export fn SizePrinter_visitor(
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
    const cursor = CXCursor.init(_cursor, _parent);
    if (!this.isAcceptable(cursor)) {
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

    // const display = CXString.initFromCursorDisplayName(_cursor);
    // defer display.deinit();
    const spelling = CXString.initFromCursorSpelling(_cursor);
    defer spelling.deinit();
    // const kind = CXString.initFromCursorKind(_cursor);
    // defer kind.deinit();
    const parent = CXString.initFromCursorSpelling(_parent);
    defer parent.deinit();

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
        c.CXCursor_StructDecl,
        => {
            // skip
        },
        // c.CXCursor_StructDecl => {
        //     const name = spelling.toString();
        //     // clang_Type_getSizeOf not support template class
        //     if (std.mem.startsWith(u8, name, "(anonymous ")) {
        //         try this.writer.writeAll("//");
        //     }
        //     try this.writer.print("size_t {s}_sizeof()", .{name});
        //     if (this.impl) {
        //         try this.writer.print("{{ return sizeof({s}); }}\n", .{
        //             name,
        //         });
        //     } else {
        //         try this.writer.writeAll(";\n");
        //     }
        // },
        c.CXCursor_FieldDecl => {
            const name = parent.toString();
            for (skip_types) |skip| {
                if (std.mem.eql(u8, name, skip)) {
                    // template ImVector
                    // skip
                    return c.CXChildVisit_Recurse;
                }
            }
            if (c.clang_Cursor_isBitField(_cursor) != 0) {
                // skip bitfield
                return c.CXChildVisit_Recurse;
            }

            // clang_Type_getSizeOf not support template class
            // clang_Cursor_getOffsetOfField not support template class field
            if (std.mem.startsWith(u8, name, "(anonymous ")) {
                try this.writer.writeAll("//");
            } else {
                const kv = try this.used.getOrPut(name);
                if (kv.found_existing) {
                    kv.value_ptr.* += 1;
                } else {
                    kv.value_ptr.* = 1;
                    if (std.mem.startsWith(u8, name, "(anonymous ")) {
                        try this.writer.writeAll("//");
                    }
                    try this.writer.print("size_t {s}_sizeof()", .{name});
                    if (this.impl) {
                        try this.writer.print("{{ return sizeof({s}); }}\n", .{
                            name,
                        });
                    } else {
                        try this.writer.writeAll(";\n");
                    }
                }
            }
            try this.writer.print("size_t {s}_offsetof_{s}()", .{
                name,
                spelling.toString(),
            });
            if (this.impl) {
                try this.writer.print("{{ return offsetof({s}, {s}); }}\n", .{
                    name,
                    spelling.toString(),
                });
            } else {
                try this.writer.writeAll(";\n");
            }
        },
        else => {
            // indent
            // try this.writeIndent();
            // try this.writer.print("[{s}] {s}\n", .{ kind.toString(), spelling.toString() });
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

fn isAcceptable(this: @This(), cursor: CXCursor) bool {
    if (cursor.isFromMainFile()) {
        return true;
    }

    const filename = CXString.initFromCursorFilepath(cursor.cursor);
    defer filename.deinit();

    // if (c.clang_getCString(cursor.filename)) |p| {
    {
        const cursor_path = filename.toString();
        // std.log.debug("{s}, {s}", .{ this.entry_point, cursor_path });
        if (std.mem.eql(u8, cursor_path, this.entry_point)) {
            return true;
        }
        for (this.include_dirs) |include| {
            if (std.mem.startsWith(u8, cursor_path, include)) {
                return true;
            }
        }
    }

    return false;
}
