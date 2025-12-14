const std = @import("std");
const cx_declaration = @import("cx_declaration.zig");

pub fn allocPrint(allocator: std.mem.Allocator, t: cx_declaration.TypeReference) ![]const u8 {
    return switch (t.ref) {
        .value => |v| allocPrintValue(allocator, v),
        .container => |container| {
            var out = std.Io.Writer.Allocating.init(allocator);
            defer out.deinit();

            try out.writer.print("pub const {s} = struct {{\n", .{container.name});
            for (container.fields) |field| {
                const type_str = try allocPrint(allocator, field.type_ref);
                defer allocator.free(type_str);
                try out.writer.print("    {s}: {s},\n", .{ field.name, type_str });
            }
            try out.writer.writeAll("};");

            return out.toOwnedSlice();
        },
        else => "not_impl",
    };
}

pub fn allocPrintValue(allocator: std.mem.Allocator, v: cx_declaration.ValueType) ![]const u8 {
    return switch (v) {
        .u8 => try allocator.dupe(u8, "u8"),
    };
}

test "allocPrint" {
    const allocator = std.testing.allocator;

    {
        const zig_src = try allocPrint(allocator, .{
            .ref = .{ .value = .{ .u8 = void{} } },
        });
        defer allocator.free(zig_src);
        try std.testing.expectEqualSlices(u8, "u8", zig_src);
    }

    {
        var type_ref = cx_declaration.TypeReference{
            .ref = .{
                .container = try cx_declaration.Container.create(allocator, "Obj", &.{
                    .{
                        .name = "value",
                        .type_ref = .{ .ref = .{ .value = .{ .u8 = void{} } } },
                    },
                }),
            },
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
