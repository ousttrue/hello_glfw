const std = @import("std");
const cx_declaration = @import("cx_declaration.zig");
const ZigGenerator = @This();

usedMap: std.StringHashMap(u32),

pub fn init(allocator: std.mem.Allocator) @This() {
    return .{
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
        .container => |container| {
            try writer.print("pub const {s} = struct {{\n", .{container.name});
            for (container.fields) |field| {
                try writer.print("    {s}: ", .{field.name});
                try _allocPrintDeref(writer, field.type_ref);
                try writer.writeAll(",\n");
            }
            try writer.writeAll("};");
        },
        .function => |function| {
            if (std.mem.startsWith(u8, function.name, "operator ")) {
                return;
            }
            const e = try this.usedMap.getOrPut(function.name);
            if (e.found_existing) {
                return;
            }
            e.value_ptr.* = 1;

            try writer.print("pub extern fn {s}(", .{function.name});
            for (function.params, 0..) |param, i| {
                if (i > 0) {
                    try writer.writeAll(", ");
                }
                try writer.print("{s}: ", .{param.name});
                try _allocPrintDeref(writer, param.type_ref);
            }
            try writer.writeAll(") ");
            try _allocPrintDeref(writer, function.ret_type);
            try writer.writeAll(";");
        },
        else => {
            return error.not_impl;
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
            try writer.writeAll("[*c]");
            try _allocPrintDeref(writer, p.type_ref);
        },
        .container => |container| {
            // only name
            try writer.print("{s}", .{container.name});
        },
        .function => {
            unreachable;
        },
        .named => |name| {
            try writer.writeAll(name);
        },
        else => {
            return error.not_impl;
        },
    }
}

fn writeValue(writer: *std.Io.Writer, v: cx_declaration.ValueType) !void {
    switch (v) {
        .void => {
            try writer.writeAll("void");
        },
        .bool => {
            try writer.writeAll("bool");
        },
        .u8 => {
            try writer.writeAll("u8");
        },
        .i8 => {
            try writer.writeAll("i8");
        },
        .i32 => {
            try writer.writeAll("i32");
        },
        .f32 => {
            try writer.writeAll("f32");
        },
        .f64 => {
            try writer.writeAll("f64");
        },
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
        try std.testing.expectEqualSlices(u8, "[*c]u8", zig_src);
    }
}

test "container" {
    const allocator = std.testing.allocator;

    {
        var zig_generator = ZigGenerator.init(allocator);
        defer zig_generator.deinit();
        var type_ref = cx_declaration.Type{
            .container = try cx_declaration.ContainerType.create(allocator, "Obj", &.{
                .{
                    .name = "value",
                    .type_ref = .{ .value = .{ .u8 = void{} } },
                },
            }),
        };
        defer type_ref.destroy(allocator);
        const zig_src = try zig_generator.allocPrintDecl(allocator, type_ref);
        defer allocator.free(zig_src);
        try std.testing.expectEqualSlices(u8,
            \\pub const Obj = struct {
            \\    value: u8,
            \\};
        , zig_src);
    }
}

test "function" {
    const allocator = std.testing.allocator;

    {
        var zig_generator = ZigGenerator.init(allocator);
        defer zig_generator.deinit();

        // u8
        var type_ref = cx_declaration.Type{
            .function = try cx_declaration.FunctionType.create(allocator, "func", .{ .value = .{ .u8 = void{} } }, &.{
                .{
                    .name = "param0",
                    .type_ref = .{ .value = .{ .u8 = void{} } },
                },
            }),
        };
        defer type_ref.destroy(allocator);
        const zig_src = try zig_generator.allocPrintDecl(allocator, type_ref);
        defer allocator.free(zig_src);
        try std.testing.expectEqualSlices(u8, "pub extern fn func(param0: u8) u8;", zig_src);
    }
    {
        var zig_generator = ZigGenerator.init(allocator);
        defer zig_generator.deinit();

        // [*c]u8
        const p_type = try allocator.create(cx_declaration.PointerType);
        p_type.* = .{
            .type_ref = .{
                .value = .{
                    .u8 = void{},
                },
            },
        };
        var type_ref = cx_declaration.Type{
            .function = try cx_declaration.FunctionType.create(allocator, "func", .{ .pointer = p_type }, &.{
                .{
                    .name = "param0",
                    .type_ref = .{ .value = .{ .u8 = void{} } },
                },
            }),
        };
        defer type_ref.destroy(allocator);
        const zig_src = try zig_generator.allocPrintDecl(allocator, type_ref);
        defer allocator.free(zig_src);
        try std.testing.expectEqualSlices(u8, "pub extern fn func(param0: u8) [*c]u8;", zig_src);
    }
    {
        var zig_generator = ZigGenerator.init(allocator);
        defer zig_generator.deinit();

        // struct Hoge
        const p_type = try cx_declaration.ContainerType.create(allocator, "Hoge", &.{
            .{
                .name = "f1",
                .type_ref = .{ .value = .{ .u8 = void{} } },
            },
            .{
                .name = "f2",
                .type_ref = .{ .value = .{ .u8 = void{} } },
            },
        });
        var type_ref = cx_declaration.Type{
            .function = try cx_declaration.FunctionType.create(allocator, "func", .{ .container = p_type }, &.{
                .{
                    .name = "param0",
                    .type_ref = .{ .value = .{ .u8 = void{} } },
                },
            }),
        };
        defer type_ref.destroy(allocator);
        const zig_src = try zig_generator.allocPrintDecl(allocator, type_ref);
        defer allocator.free(zig_src);
        try std.testing.expectEqualSlices(u8,
            \\pub extern fn func(param0: u8) Hoge;
        , zig_src);
    }
    {
        var zig_generator = ZigGenerator.init(allocator);
        defer zig_generator.deinit();

        // [*c]Hoge
        const inner_type = try cx_declaration.ContainerType.create(allocator, "Hoge", &.{
            .{
                .name = "f1",
                .type_ref = .{ .value = .{ .u8 = void{} } },
            },
            .{
                .name = "f2",
                .type_ref = .{ .value = .{ .u8 = void{} } },
            },
        });
        const p_type = try allocator.create(cx_declaration.PointerType);
        p_type.* = .{
            .type_ref = .{
                .container = inner_type,
            },
        };
        var type_ref = cx_declaration.Type{
            .function = try cx_declaration.FunctionType.create(allocator, "func", cx_declaration.Type{ .pointer = p_type }, &.{
                .{
                    .name = "param0",
                    .type_ref = .{ .value = .{ .u8 = void{} } },
                },
            }),
        };
        defer type_ref.destroy(allocator);
        const zig_src = try zig_generator.allocPrintDecl(allocator, type_ref);
        defer allocator.free(zig_src);
        try std.testing.expectEqualSlices(u8,
            \\pub extern fn func(param0: u8) [*c]Hoge;
        , zig_src);
    }
}
