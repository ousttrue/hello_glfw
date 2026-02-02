const std = @import("std");
const c = @import("cindex");
const cxtype_kind = @import("cxtype_kind.zig");
const CXCursor = @import("CXCursor.zig");

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

pub const ContainerType = struct {
    pub const Field = struct {
        name: []const u8,
        type_ref: Type,
    };

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

pub const FunctionType = struct {
    pub const Param = struct {
        name: []const u8,
        type_ref: Type,
    };

    name: []const u8,
    ret_type: Type,
    params: []const Param,

    pub fn create(
        allocator: std.mem.Allocator,
        name: []const u8,
        ret_type: Type,
        params: []const Param,
    ) !*@This() {
        const this = try allocator.create(@This());
        this.* = .{
            .name = name,
            .ret_type = ret_type,
            .params = params,
        };
        return this;
    }

    pub fn destroy(this: *const @This(), allocator: std.mem.Allocator) void {
        this.ret_type.destroy(allocator);
        for (this.params) |*param| {
            param.type_ref.destroy(allocator);
        }
        allocator.destroy(this);
    }
};

pub const EnumType = struct {
    pub const Value = struct {
        name: []const u8,
        value: i32,
    };

    name: []const u8,
    values: []Value,

    pub fn create(
        allocator: std.mem.Allocator,
        name: []const u8,
        values: []const Value,
    ) !*@This() {
        const this = try allocator.create(@This());
        this.* = .{
            .name = name,
            .values = values,
        };
        return this;
    }

    pub fn destroy(this: *const @This(), allocator: std.mem.Allocator) void {
        allocator.destroy(this);
    }
};

pub const Type = union(enum) {
    value: ValueType,
    pointer: *PointerType,
    container: *ContainerType,
    function: *FunctionType,
    int_enum: *EnumType,

    pub fn createFromCursor(allocator: std.mem.Allocator, cursor: CXCursor) !?@This() {
        switch (cursor.cursor.kind) {
            c.CXCursor_FunctionDecl => {
                return .{
                    .function = try FunctionType.create(
                        allocator,
                        cursor.getSpelling(),
                        .{ .value = .{ .u8 = void{} } },
                        &.{},
                    ),
                };
            },
            else => {
                @panic("UNKNOWN");
            },
        }
    }

    pub fn destroy(this: *const @This(), allocator: std.mem.Allocator) void {
        switch (this.*) {
            .value => {},
            .pointer => |pointer| {
                pointer.destroy(allocator);
            },
            .container => |container| {
                container.destroy(allocator);
            },
            .function => |function| {
                function.destroy(allocator);
            },
            .int_enum => {
                @panic("not impl");
            },
        }
    }
};
