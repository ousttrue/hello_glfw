const std = @import("std");
const cx_declaration = @import("cx_declaration.zig");

pub fn allocPrint(allocator: std.mem.Allocator, t: cx_declaration.TypeReference) ![]const u8 {
    return switch (t.reference) {
        .value => |v| allocPrintValue(allocator, v),
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
            .reference = .{
                .value = .{ .u8 = void{} },
            },
        });
        defer allocator.free(zig_src);
        try std.testing.expectEqualSlices(u8, "u8", zig_src);
    }

    // try std.testing.expectEqualSlices(u8,
    //     \\const Obj = struct {
    //     \\  value: u8,
    //     \\};
    // , try allocPrint(allocator, .{
    //     .object = .{
    //         .name = "Obj",
    //         .fields = &.{
    //             .{ .name = "value", .type_ref = .{
    //                 .value = .{ .u8 = void{} },
    //             } },
    //         },
    //     },
    // }));
}
