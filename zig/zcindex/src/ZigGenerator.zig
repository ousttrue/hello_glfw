const std = @import("std");
const cx_declaration = @import("cx_declaration.zig");
const ZigGenerator = @This();

const skip_types = [_][]const u8{
    // template ImVector
    "ImVector",
    // ImGuiTextFilter::ImGuiTextRange
    "ImGuiTextRange",
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
usedMap: std.StringHashMap(u32),

pub fn init(allocator: std.mem.Allocator) @This() {
    return .{
        .allocator = allocator,
        .usedMap = .init(allocator),
    };
}

pub fn deinit(this: *@This()) void {
    this.usedMap.deinit();
}

pub fn allocPrintDecl(this: *@This(), allocator: std.mem.Allocator, t: cx_declaration.Type) ![]const u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try this._allocPrintDecl(&out.writer, t);
    return out.toOwnedSlice();
}

fn _allocPrintDecl(this: *@This(), writer: *std.Io.Writer, t: cx_declaration.Type) !void {
    switch (t) {
        .value => |v| {
            try writeValue(writer, v);
        },
        .pointer => |p| {
            try _allocPrintDeref(writer, p.type_ref);
        },
        .array => |a| {
            try _allocPrintDeref(writer, a.type_ref);
        },
        .typedef => |typedef| {
            const name = typedef.name.toString();
            const e = try this.usedMap.getOrPut(name);
            if (e.found_existing) {
                return;
            }
            e.value_ptr.* = 1;

            try writer.print("pub const {s} = ", .{name});
            try _allocPrintDeref(writer, typedef.type_ref);
            try writer.writeAll(";");
        },
        .container => |container| {
            const name = container.name.toString();

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

            try writer.print("pub const {s} = struct {{\n", .{name});
            for (container.fields) |field| {
                try writer.print("    {s}: ", .{field.name.toString()});
                try _allocPrintDeref(writer, field.type_ref);
                try writer.writeAll(",\n");
            }
            try writer.writeAll("};\n");

            // Test
            // try writer.print("test \"{s}\" {{\n", .{name});
            // try writer.writeAll("}");
            // 
            for(skip_types)|skip|{
                if(std.mem.eql(u8, name, skip)){
                    return;
                }
            }
            try writer.print(
                \\test "{s}" {{
                \\try std.testing.expectEqual(@sizeOf({s}), c.{s}_sizeof());
                \\}}
                \\
            , .{ name, name, name });
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
                try writer.print("{s}: ", .{param.name});
                try _allocPrintDeref(writer, param.type_ref);
            }
            try writer.writeAll(") ");
            try _allocPrintDeref(writer, function.ret_type);
            try writer.writeAll(";\n");
            try writer.print("pub const {s} = {s};", .{ name, mangling });
        },
        .named => {
            unreachable;
        },
    }
}

fn allocPrintDeref(allocator: std.mem.Allocator, t: cx_declaration.Type) ![]const u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try _allocPrintDeref(&out.writer, t);
    return out.toOwnedSlice();
}

fn _allocPrintDeref(writer: *std.Io.Writer, t: cx_declaration.Type) !void {
    switch (t) {
        .value => |v| {
            try writeValue(writer, v);
        },
        .pointer => |p| {
            if (std.meta.eql(p.type_ref, cx_declaration.Type{ .value = .void })) {
                try writer.writeAll("?*anyopaque");
            } else {
                try writer.writeAll("?*");
                try _allocPrintDeref(writer, p.type_ref);
            }
        },
        .array => |a| {
            try writer.print("[{}]", .{a.len});
            try _allocPrintDeref(writer, a.type_ref);
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
        });
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
        const zig_src = try allocPrintDeref(allocator, type_ref);
        defer allocator.free(zig_src);
        try std.testing.expectEqualSlices(u8, "?*u8", zig_src);
    }
}
