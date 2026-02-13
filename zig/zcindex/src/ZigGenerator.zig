const std = @import("std");
const c = @import("cindex");
const cx_declaration = @import("cx_declaration.zig");
const ZigGenerator = @This();
const cx_util = @import("cx_util.zig");
const CXString = @import("CXString.zig");

const skip_types = [_][]const u8{
    // template ImVector
    "ImVector",
    // ImGuiTextFilter::ImGuiTextRange
    "ImGuiTextFilter",
    "ImGuiTextRange",
    // bitfield, union member
    "ImFontGlyph",
    "ImFontAtlas",
    "ImFontBaked",
    "ImGuiPlatformImeData",
    "ImGuiStoragePair",
    // "ImGuiStorage",
};

const opaque_names = [_][]const u8{
    "ImGuiContext",
    "ImDrawListSharedData",
    "ImFontLoader",
    "ImFontAtlasBuilder",
};

const c_to_zig = std.StaticStringMap([]const u8).initComptime(&.{
    .{ "char", "u8" },
    .{ "float", "f32" },
});

allocator: std.mem.Allocator,
writer: *std.Io.Writer,
entry_point: []const u8,
include_dirs: []const []const u8,
usedMap: std.StringHashMap(u32),

pub fn init(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    entry_point: []const u8,
    include_dirs: []const []const u8,
) @This() {
    writer.writeAll(
        \\const std = @import("std");
        \\const glfw = @import("glfw");
        \\const GLFWwindow = glfw.GLFWwindow;
        \\const GLFWmonitor = glfw.GLFWmonitor;
        \\
        \\pub const c = @cImport({
        \\    @cInclude("size_offset.h");
        \\});
        \\
        \\pub fn ImVector(T: type) type {
        \\    return extern struct {
        \\        Size: i32,
        \\        Capacity: i32,
        \\        Data: *T,
        \\    };
        \\}
        \\
        \\pub const ImGuiStoragePair = struct {
        \\    key: ImGuiID,
        \\    val_p: *anyopaque,
        \\};
        \\
        \\pub const ImFontBaked = opaque{};
        \\pub const ImFontAtlas = opaque{};
        \\
        \\
    ) catch unreachable;

    return .{
        .allocator = allocator,
        .writer = writer,
        .entry_point = entry_point,
        .include_dirs = include_dirs,
        .usedMap = .init(allocator),
    };
}

pub fn deinit(this: *@This()) void {
    this.usedMap.deinit();
}

pub export fn ZigGenerator_visitor(
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
    _ = _parent;
    // const cursor = CXCursor.init(_cursor, _parent);
    if (!cx_util.isAcceptable(_cursor, this.entry_point, this.include_dirs)) {
        // skip
        return c.CXVisit_Continue;
    }
    // try this.cursors.append(this.allocator, cursor);

    if (try cx_declaration.Type.createFromCursor(this.allocator, _cursor)) |decl| {
        defer decl.destroy(this.allocator);
        const zig_src = try allocPrintDecl(this, this.allocator, decl, false);
        defer this.allocator.free(zig_src);
        if (zig_src.len > 0) {
            try this.writer.print("{s}\n", .{zig_src});
        }
    }

    return switch (_cursor.kind) {
        // c.CXCursor_Namespace => c.CXChildVisit_Recurse,
        // c.CXCursor_StructDecl => c.CXChildVisit_Recurse,
        // c.CXCursor_EnumDecl => c.CXChildVisit_Recurse,
        // c.CXCursor_FunctionDecl => c.CXChildVisit_Recurse,

        c.CXCursor_Namespace => c.CXChildVisit_Recurse,
        else => c.CXChildVisit_Continue,
    };
}
// for (data.cursors.items) |cursor| {
// }

pub fn allocPrintDecl(this: *@This(), allocator: std.mem.Allocator, t: cx_declaration.Type, is_param: bool) ![]const u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try this._allocPrintDecl(&out.writer, t, is_param);
    return out.toOwnedSlice();
}

fn _allocPrintDecl(this: *@This(), writer: *std.Io.Writer, t: cx_declaration.Type, is_param: bool) !void {
    switch (t) {
        .value => |v| {
            try writeValue(writer, v);
        },
        .pointer => |p| {
            try _allocPrintDeref(writer, p.type_ref, is_param);
        },
        .array => |a| {
            try _allocPrintDeref(writer, a.type_ref, is_param);
        },
        .typedef => |typedef| {
            const name = typedef.name.toString();
            const e = try this.usedMap.getOrPut(name);
            if (e.found_existing) {
                return;
            }
            e.value_ptr.* = 1;

            try writer.print("pub const {s} = ", .{name});
            try _allocPrintDeref(writer, typedef.type_ref, is_param);
            try writer.writeAll(";");
        },
        .container => |container| {
            const name = container.name.toString();
            for (skip_types) |skip| {
                if (std.mem.eql(u8, name, skip)) {
                    return;
                }
            }

            for (opaque_names) |opaque_name| {
                if (std.mem.eql(u8, name, opaque_name)) {
                    try writer.print("pub const {s} = opaque{{}};", .{name});
                    return;
                }
            }

            if (container.fields.len == 0) {
                return;
            }
            const e = try this.usedMap.getOrPut(name);
            if (e.found_existing) {
                return;
            }
            e.value_ptr.* = 1;

            try writer.print("pub const {s} = extern struct {{\n", .{name});
            for (container.fields) |field| {
                try writer.print("    {s}: ", .{field.name.toString()});
                try _allocPrintDeref(writer, field.type_ref, false);
                try writer.writeAll(",\n");
            }
            try writer.writeAll("};\n");

            // Test
            // try writer.print("test \"{s}\" {{\n", .{name});
            // try writer.writeAll("}");
            //
            try writer.print(
                \\test "{s}" {{
                \\
            , .{name});

            try writer.print(
                "try std.testing.expectEqual(@sizeOf({s}), c.{s}_sizeof());\n",
                .{ name, name },
            );
            for (container.fields) |field| {
                try writer.print(
                    "try std.testing.expectEqual(@offsetOf({s}, \"{s}\"), c.{s}_offsetof_{s}());\n",
                    .{ name, field.name.toString(), name, field.name.toString() },
                );
            }
            try writer.writeAll("}\n");
        },
        .int_enum => |int_enum| {
            const name = int_enum.name.toString();
            if (int_enum.values.len == 0) {
                return;
            }
            const e = try this.usedMap.getOrPut(name);
            if (e.found_existing) {
                return;
            }
            e.value_ptr.* = 1;

            if (std.mem.endsWith(u8, name, "_")) {
                for (int_enum.values) |value| {
                    try writer.print("pub const {s} = {};\n", .{ value.name.toString(), value.value });
                }
            } else {
                var used: std.AutoHashMap(i64, u32) = .init(this.allocator);
                defer used.deinit();

                try writer.print("pub const {s} = enum(i32) {{\n", .{name});
                for (int_enum.values) |value| {
                    const kv = try used.getOrPut(value.value);
                    if (kv.found_existing) {
                        kv.value_ptr.* += 1;
                    } else {
                        kv.value_ptr.* = 1;
                        try writer.print("    {s} = {},\n", .{ value.name.toString(), value.value });
                    }
                }
                try writer.writeAll("};");
            }
        },
        .function => |function| {
            const name = function.name.toString();
            const mangling = function.mangling.toString();
            if (std.mem.startsWith(u8, name, "operator ")) {
                return;
            }
            const e = try this.usedMap.getOrPut(name);
            if (e.found_existing) {
                return;
            }
            e.value_ptr.* = 1;

            try writer.print("extern fn {s}(", .{mangling});
            for (function.params, 0..) |param, i| {
                if (i > 0) {
                    try writer.writeAll(", ");
                }
                try writer.print("{s}: ", .{param.name.toString()});
                try _allocPrintDeref(writer, param.type_ref, true);
            }
            if (function.is_variadic) {
                try writer.writeAll(", ...");
            }
            try writer.writeAll(") ");
            try _allocPrintDeref(writer, function.ret_type, false);
            try writer.writeAll(";\n");
            try writer.print("pub const {s} = {s};", .{ name, mangling });
        },
        .named => {
            unreachable;
        },
    }
}

fn allocPrintDeref(allocator: std.mem.Allocator, t: cx_declaration.Type, is_param: bool) ![]const u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try _allocPrintDeref(&out.writer, t, is_param);
    return out.toOwnedSlice();
}

fn _allocPrintDeref(writer: *std.Io.Writer, t: cx_declaration.Type, is_param: bool) !void {
    switch (t) {
        .value => |v| {
            try writeValue(writer, v);
        },
        .pointer => |p| {
            if (std.meta.eql(p.type_ref, cx_declaration.Type{ .value = .void })) {
                try writer.writeAll("?*anyopaque");
            } else {
                try writer.writeAll("?*");
                try _allocPrintDeref(writer, p.type_ref, is_param);
            }
        },
        .array => |a| {
            if (is_param) {
                // as pointer
                try writer.writeAll("?*");
                try _allocPrintDeref(writer, a.type_ref, is_param);
            } else {
                try writer.print("[{}]", .{a.len});
                try _allocPrintDeref(writer, a.type_ref, is_param);
            }
        },
        .container => |container| {
            // only name
            try writer.print("{s}", .{container.name.toString()});
        },
        .function => {
            unreachable;
        },
        .named => |named| {
            const name = named.toString();
            if (std.mem.startsWith(u8, name, "ImVector<")) {
                try writer.writeAll("ImVector(");
                const inner_type = name[9 .. name.len - 1];
                if (std.mem.endsWith(u8, inner_type, "*")) {
                    // pointer
                    try writer.writeAll("*anyopaque");
                } else if (c_to_zig.get(inner_type)) |zig_type| {
                    // char etc...
                    try writer.writeAll(zig_type);
                } else {
                    // ImWchar etc...
                    try writer.writeAll(inner_type);
                }

                try writer.writeAll(")");
            } else {
                try writer.writeAll(name);
            }
        },
        else => {
            return error.not_impl;
        },
    }
}

fn writeValue(writer: *std.Io.Writer, v: cx_declaration.ValueType) !void {
    switch (v) {
        .void => try writer.writeAll("void"),
        .bool => try writer.writeAll("bool"),
        //
        .u8 => try writer.writeAll("u8"),
        .u16 => try writer.writeAll("u16"),
        .u32 => try writer.writeAll("u32"),
        .u64 => try writer.writeAll("u64"),
        //
        .i8 => try writer.writeAll("i8"),
        .i16 => try writer.writeAll("i16"),
        .i32 => try writer.writeAll("i32"),
        .i64 => try writer.writeAll("i64"),
        //
        .f32 => try writer.writeAll("f32"),
        .f64 => try writer.writeAll("f64"),
    }
}

test "value" {
    const allocator = std.testing.allocator;

    {
        const zig_src = try allocPrintDeref(allocator, .{
            .value = .{ .u8 = void{} },
        }, false);
        defer allocator.free(zig_src);
        try std.testing.expectEqualSlices(u8, "u8", zig_src);
    }
}

test "pointer" {
    const allocator = std.testing.allocator;

    {
        const type_ref = cx_declaration.Type{
            .pointer = try cx_declaration.PointerType.create(allocator, .{
                .value = .{ .u8 = void{} },
            }),
        };
        defer type_ref.destroy(allocator);
        const zig_src = try allocPrintDeref(allocator, type_ref, false);
        defer allocator.free(zig_src);
        try std.testing.expectEqualSlices(u8, "?*u8", zig_src);
    }
}
