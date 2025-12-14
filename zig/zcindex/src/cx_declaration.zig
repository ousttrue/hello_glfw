const std = @import("std");
const c = @import("cindex");
const cxtype_kind = @import("cxtype_kind.zig");

pub const ValueType = union(enum) {
    u8,
};

pub const StructType = struct {};

pub const PoinerType = struct {};

pub const FunctionType = struct {};

pub const EnumType = struct {};

pub const Type = union(enum) {
    value: ValueType,
    pointer: PoinerType,
    object: StructType,
    function: FunctionType,
    int_enum: EnumType,
};

pub const TypeReference = struct {
    reference: Type,
};

// pub const DeclarationType = enum {
//     function,
//     pointer,
// };
//
// pub const FunctionType = struct {
//     allocator: std.mem.Allocator,
//     name: []const u8,
//     return_type: Declaration,
// };
//
// pub const PointerType = struct {
//     allocator: std.mem.Allocator,
// };
//
// pub const Declaration = union(DeclarationType) {
//     function: *FunctionType,
//     pointer: *PointerType,
//
//     pub fn createFromCXType(allocator: std.mem.Allocator, cxtype: c.CXType) !*@This() {
//         const this = try allocator.create(@This());
//         switch (cxtype.kind) {
//             c.CXType_Pointer => {},
//             else => {
//                 std.log.err("{s}", .{cxtype_kind.toName(cxtype.kind)});
//                 @panic("not impl");
//             },
//         }
//         return this;
//     }
//
//     pub fn destroy(this: *@This()) void {
//         this.allocator.destroy(this);
//     }
// };
