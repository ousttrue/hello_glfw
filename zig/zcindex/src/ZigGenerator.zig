const std = @import("std");
const c = @import("cindex");
const cx_declaration = @import("cx_declaration.zig");
const ZigGenerator = @This();
const CXLocation = @import("CXLocation.zig");
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

const multi_object = [_][]const u8{
    "u8",
    // "ImFontAtlas",
    // "ImFontBaked",
    // "GLFWmonitor",
    // "GLFWwindow",
    // "ImGuiContext",
    // "ImDrawListSharedData",
    // "ImFontLoader",
    // "ImGuiIO",
};

const c_to_zig = std.StaticStringMap([]const u8).initComptime(&.{
    .{ "char", "u8" },
    .{ "float", "f32" },
});

allocator: std.mem.Allocator,
src_map: std.StringHashMap([]const u8),
writer: *std.Io.Writer,
entry_point: []const u8,
include_dirs: []const []const u8,
funcUsedMap: std.StringHashMap(u32),

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
        .src_map = .init(allocator),
        .writer = writer,
        .entry_point = entry_point,
        .include_dirs = include_dirs,
        .funcUsedMap = .init(allocator),
    };
}

pub fn deinit(this: *@This()) void {
    var it = this.src_map.iterator();
    while (it.next()) |e| {
        this.allocator.free(e.value_ptr.*);
    }
    this.src_map.deinit();
    this.funcUsedMap.deinit();
}

pub export fn ZigGenerator_visitor(
    cursor: c.CXCursor,
    parent: c.CXCursor,
    client_data: c.CXClientData,
) c.CXChildVisitResult {
    const data: *@This() = @ptrCast(@alignCast(client_data));
    return data.onVisit(cursor, parent) catch |e| {
        @panic(@errorName(e));
        // return c.CXChildVisit_Break;
    };
}

fn onVisit(
    this: *@This(),
    _cursor: c.CXCursor,
    _parent: c.CXCursor,
) !c.CXChildVisitResult {
    _ = _parent;
    // const cursor = CXCursor.init(_cursor, _parent);
    if (!CXLocation.isAcceptable(_cursor, this.entry_point, this.include_dirs)) {
        // skip
        return c.CXVisit_Continue;
    }
    // try this.cursors.append(this.allocator, cursor);

    if (try cx_declaration.Type.createFromCursor(this.allocator, &this.src_map, _cursor)) |decl| {
        defer decl.destroy(this.allocator);
        const zig_src = try allocPrintDecl(this, this.allocator, decl, false);
        defer this.allocator.free(zig_src);
        if (zig_src.len > 0) {
            try this.writer.print("{s}\n", .{zig_src});
        }
    }

    return switch (_cursor.kind) {
        c.CXCursor_Namespace => c.CXChildVisit_Recurse,
        // c.CXCursor_StructDecl => c.CXChildVisit_Recurse,
        // c.CXCursor_EnumDecl => c.CXChildVisit_Recurse,
        // c.CXCursor_FunctionDecl => c.CXChildVisit_Recurse,
        else => c.CXChildVisit_Continue,
    };
}

pub fn allocPrintDecl(this: *@This(), allocator: std.mem.Allocator, t: cx_declaration.Type, is_param: bool) ![]const u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try this._allocPrintDecl(&out.writer, t, is_param);
    return out.toOwnedSlice();
}

// -360.0f
// +360.0f
fn writerAsZig(t: cx_declaration.Type, writer: *std.io.Writer, c_expression: []const u8) !void {
    switch (t) {
        .value => |v| {
            switch (v) {
                .f32 => {
                    if (std.mem.eql(u8, c_expression, "FLT_MAX")) {
                        try writer.print("{}", .{std.math.floatMax(f32)});
                    } else {
                        var exp = c_expression;
                        if (exp[exp.len - 1] == 'f') {
                            exp = exp[0 .. exp.len - 1];
                        }
                        // std.log.err("{s}", .{exp});
                        const f = try std.fmt.parseFloat(f32, exp);
                        try writer.print("{}", .{f});
                    }
                },
                else => {
                    if (std.mem.eql(u8, c_expression, "sizeof(float)")) {
                        try writer.writeAll("@sizeOf(f32)");
                    } else {
                        try writer.writeAll(c_expression);
                    }
                },
            }
        },
        .typedef => {
            try writer.writeAll("##typedef##");
        },
        .pointer => {
            if (std.mem.eql(u8, c_expression, "NULL") or
                std.mem.eql(u8, c_expression, "nullptr"))
            {
                try writer.writeAll("null");
            } else if (std.mem.eql(u8, c_expression, "ImVec2(0, 0)") or
                std.mem.eql(u8, c_expression, "ImVec2(0.0f, 0.0f)"))
            {
                try writer.writeAll("&.{ .x=0, .y=0 }");
            } else if (std.mem.eql(u8, c_expression, "ImVec2(-FLT_MIN, 0)")) {
                try writer.writeAll("&.{ .x=-std.math.floatMin(f32), .y=0 }");
            } else if (std.mem.eql(u8, c_expression, "ImVec2(1, 1)")) {
                try writer.writeAll("&.{ .x=1, .y=1 }");
            } else if (std.mem.eql(u8, c_expression, "ImVec4(0, 0, 0, 0)")) {
                try writer.writeAll("&.{ .x=0, .y=0, .z=0, .w=0 }");
            } else if (std.mem.eql(u8, c_expression, "ImVec4(1, 1, 1, 1)")) {
                try writer.writeAll("&.{ .x=1, .y=1, .z=1, .w=1 }");
            } else if (c_expression[0] == '"' and c_expression[c_expression.len - 1] == '"') {
                try writer.writeAll(c_expression);
            } else {
                try writer.print("##pointer=>{s}", .{c_expression});
            }
        },
        .array => {
            try writer.print("##array=>{s}##", .{c_expression});
        },
        .container => {
            try writer.print("##container=>{s}##", .{c_expression});
        },
        .function => {
            try writer.print("##function=>{s}##", .{c_expression});
        },
        .int_enum => {
            try writer.print("##int_enum=>{s}##", .{c_expression});
        },
        .named => {
            // try writer.print("##named=>{s}##", .{c_expression});
            if (std.mem.eql(u8, c_expression, "NULL")) {
                try writer.writeAll("null");
            } else {
                try writer.writeAll(c_expression);
            }
        },
    }
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
            // const e = try this.usedMap.getOrPut(name);
            // if (e.found_existing) {
            //     return;
            // }
            // e.value_ptr.* = 1;

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
            // const e = try this.usedMap.getOrPut(name);
            // if (e.found_existing) {
            //     return;
            // }
            // e.value_ptr.* = 1;

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
            // const e = try this.usedMap.getOrPut(name);
            // if (e.found_existing) {
            //     return;
            // }
            // e.value_ptr.* = 1;

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
            var name_buf: [128]u8 = undefined;
            var name = function.name.toString();
            const mangling = function.mangling.toString();
            if (std.mem.startsWith(u8, name, "operator ")) {
                return;
            }
            const e = try this.funcUsedMap.getOrPut(name);
            if (e.found_existing) {
                e.value_ptr.* += 1;
                name = try std.fmt.bufPrint(&name_buf, "{s}_{}", .{ name, e.value_ptr.* });
            } else {
                e.value_ptr.* = 1;
            }

            //
            // extern fn {mangling}
            //
            try writer.print("extern fn {s}(", .{mangling});
            for (function.params, 0..) |param, i| {
                if (i > 0) {
                    try writer.writeAll(", ");
                }
                try writer.print("{s}: ", .{param.getName()});
                try _allocPrintDeref(writer, param.type_ref, true);
            }
            if (function.is_variadic) {
                try writer.writeAll(", ...");
            }
            try writer.writeAll(") ");
            try _allocPrintDeref(writer, function.ret_type, false);
            try writer.writeAll(";\n");
            //
            // pub fn fn_name(p0: t0, opts: struct{
            //   p1: t1 = default_value,
            // }) ret_type
            try writer.print("pub fn {s}(", .{name});
            var has_args: ?usize = null;
            var has_default: ?usize = null;
            for (function.params, 0..) |param, i| {
                if (i > 0) {
                    try writer.writeAll(", ");
                }
                if (param.default != null) {
                    has_default = i;
                    break;
                }
                has_args = i;
                try writer.print("{s}: ", .{param.getName()});
                try _allocPrintDeref(writer, param.type_ref, true);
            }
            if (has_default) |default_index| {
                try writer.writeAll("__opts__: struct{\n");
                for (default_index..function.params.len) |i| {
                    const param = function.params[i];
                    // std.debug.assert(param.default != null);
                    try writer.print("    {s}: ", .{param.getName()});
                    try _allocPrintDeref(writer, param.type_ref, true);
                    if (param.default) |default| {
                        try writer.writeAll(" = ");
                        try writerAsZig(param.type_ref, writer, default);
                    } else {
                        try writer.writeAll(" = .{}");
                    }
                    try writer.writeAll(",\n");
                }
                try writer.writeAll("}");
            } else if (function.is_variadic) {
                try writer.writeAll(", __vargs__: anytype");
            }
            try writer.writeAll(")");
            try _allocPrintDeref(writer, function.ret_type, false);
            //
            // body
            //
            try writer.writeAll("{\n");
            try writer.writeAll("    const __args__ = ");
            var prefix: []const u8 = "";
            if (has_args != null) {
                // args
                try writer.writeAll(prefix);
                prefix = "++";
                try writer.writeAll(".{");
                for (function.params, 0..) |param, i| {
                    if (param.default != null) {
                        break;
                    }
                    if (i > 0) {
                        try writer.writeAll(", ");
                    }
                    try writer.print("{s}", .{param.getName()});
                }
                try writer.writeAll("}");
            }
            if (has_default) |default_index| {
                // opts
                try writer.writeAll(prefix);
                prefix = "++";
                try writer.writeAll(".{");
                for (default_index..function.params.len) |i| {
                    const param = function.params[i];
                    try writer.print("__opts__.{s},", .{param.getName()});
                }
                try writer.writeAll("}");
            }
            if (function.is_variadic) {
                try writer.writeAll(prefix);
                prefix = "++";
                try writer.writeAll("__vargs__");
            }
            if (prefix.len == 0) {
                try writer.writeAll(".{}");
            }
            try writer.writeAll(";\n");

            try writer.print("    return @call(.auto, {s}, __args__);\n", .{mangling});
            try writer.writeAll("}\n");
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
                var buf: [128]u8 = undefined;
                var fbuf = std.heap.FixedBufferAllocator.init(&buf);
                const fixalloc = fbuf.allocator();
                var out = std.Io.Writer.Allocating.init(fixalloc);
                defer out.deinit();
                try _allocPrintDeref(&out.writer, p.type_ref, is_param);
                const slice = try out.toOwnedSlice();
                var is_multi = false;
                for (multi_object) |name| {
                    if (std.mem.eql(u8, name, slice)) {
                        is_multi = true;
                        break;
                    }
                }
                if (is_multi) {
                    try writer.writeAll("?[*]");
                } else {
                    try writer.writeAll("?*");
                }

                if (p.is_const) {
                    try writer.writeAll("const ");
                }
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
            var name = named.toString();
            if (std.mem.startsWith(u8, name, "const ")) {
                name = name[6..];
            }
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
        .i8 => try writer.writeAll("u8"),
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
            }, false),
        };
        defer type_ref.destroy(allocator);
        const zig_src = try allocPrintDeref(allocator, type_ref, false);
        defer allocator.free(zig_src);
        try std.testing.expectEqualSlices(u8, "?*u8", zig_src);
    }
}
