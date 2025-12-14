const std = @import("std");
const c = @import("cindex");
const cxtype_kind = @import("cxtype_kind.zig");

pub const ValueType = union(enum) {
    u8,
};

pub const PointerType = struct {
    type_ref: Type,

    pub fn create(
        allocator: std.mem.Allocator,
        type_ref: Type,
    ) !*@This() {
        const this = try allocator.create(@This());
        this.* = .{
            .type_ref = type_ref,
        };
        return this;
    }

    pub fn destroy(this: *const @This(), allocator: std.mem.Allocator) void {
        this.type_ref.destroy(allocator);
        allocator.destroy(this);
    }
};

pub const Field = struct {
    name: []const u8,
    type_ref: Type,
};

pub const ContainerType = struct {
    name: []const u8,
    fields: []const Field,

    pub fn create(
        allocator: std.mem.Allocator,
        name: []const u8,
        fields: []const Field,
    ) !*@This() {
        const this = try allocator.create(@This());
        this.* = .{
            .name = name,
            .fields = fields,
        };
        return this;
    }

    pub fn destroy(this: *const @This(), allocator: std.mem.Allocator) void {
        for (this.fields) |*field| {
            field.type_ref.destroy(allocator);
        }
        allocator.destroy(this);
    }
};

pub const FunctionType = struct {};

pub const EnumType = struct {};

pub const Type = union(enum) {
    value: ValueType,
    pointer: *PointerType,
    container: *ContainerType,
    function: *FunctionType,
    int_enum: *EnumType,

    pub fn destroy(this: *const @This(), allocator: std.mem.Allocator) void {
        switch (this.*) {
            .value => {},
            .pointer => |pointer| {
                pointer.destroy(allocator);
            },
            .container => |container| {
                container.destroy(allocator);
            },
            .function => {
                @panic("not impl");
            },
            .int_enum => {
                @panic("not impl");
            },
        }
    }
};
