const std = @import("std");
const cx_declaration = @import("cx_declaration.zig");

pub fn allocPrint(allocator: std.mem.Allocator, t: cx_declaration.Type) ![]const u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try write(&out.writer, t);
    return out.toOwnedSlice();
}

pub fn write(writer: *std.Io.Writer, t: cx_declaration.Type) !void {
    switch (t) {
        .value => |v| {
            try writeValue(writer, v);
        },
        .container => |container| {
            try writer.print("pub const {s} = struct {{\n", .{container.name});
            for (container.fields) |field| {
                try writer.print("    {s}: ", .{field.name});
                try write(writer, field.type_ref);
                try writer.writeAll(",\n");
            }
            try writer.writeAll("};");
        },
        else => {
            return error.not_impl;
        },
    }
}

pub fn writeValue(writer: *std.Io.Writer, v: cx_declaration.ValueType) !void {
    switch (v) {
        .u8 => {
            try writer.writeAll("u8");
        },
    }
}

test "allocPrint" {
    const allocator = std.testing.allocator;

    {
        const zig_src = try allocPrint(allocator, .{
            .value = .{ .u8 = void{} },
        });
        defer allocator.free(zig_src);
        try std.testing.expectEqualSlices(u8, "u8", zig_src);
    }

    {
        var type_ref = cx_declaration.Type{
            .container = try cx_declaration.Container.create(allocator, "Obj", &.{
                .{
                    .name = "value",
                    .type_ref = .{ .value = .{ .u8 = void{} } },
                },
            }),
        };
        defer type_ref.destroy(allocator);
        const zig_src = try allocPrint(allocator, type_ref);
        defer allocator.free(zig_src);
        try std.testing.expectEqualSlices(u8,
            \\pub const Obj = struct {
            \\    value: u8,
            \\};
        , zig_src);
    }
}
