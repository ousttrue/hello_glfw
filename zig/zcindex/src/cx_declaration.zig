const std = @import("std");
const c = @import("cindex");
const CXCursor = @import("CXCursor.zig");
const CXString = @import("CXString.zig");

pub const ValueType = union(enum) {
    void,
    bool,
    u8,
    i8,
    i32,
    f32,
    f64,
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
            .fields = try allocator.dupe(Field, fields),
        };
        return this;
    }

    pub fn destroy(this: *const @This(), allocator: std.mem.Allocator) void {
        for (this.fields) |*field| {
            field.type_ref.destroy(allocator);
        }
        allocator.free(this.fields);
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
    named: []const u8,

    pub fn createFromCursor(allocator: std.mem.Allocator, cursor: CXCursor) !?@This() {
        switch (cursor.cursor.kind) {
            c.CXCursor_FunctionDecl => {
                const ret_type = try createFromType(allocator, c.clang_getCursorResultType(cursor.cursor));
                return .{
                    .function = try FunctionType.create(
                        allocator,
                        cursor.getSpelling(),
                        ret_type,
                        &.{},
                    ),
                };
            },
            c.CXCursor_MacroDefinition,
            c.CXCursor_MacroExpansion,
            c.CXCursor_InclusionDirective,
            c.CXCursor_TypedefDecl,
            c.CXCursor_StructDecl,
            c.CXCursor_EnumDecl,
            c.CXCursor_FunctionTemplate,
            c.CXCursor_ClassTemplate,
            c.CXCursor_CXXMethod,
            c.CXCursor_Namespace,
            => {
                return null;
            },
            else => {
                const str = CXString.initFromCursorKind(cursor.cursor);
                defer str.deinit();
                std.log.warn("cursor.type [{s}]", .{str.toString()});
                @panic("UNKNOWN");
            },
        }
    }

    // https://clang.llvm.org/docs/LibClang.html
    // https://github.com/ousttrue/luajitffi/blob/master/clangffi/types.lua
    pub fn createFromType(allocator: std.mem.Allocator, cx_type: c.CXType) !@This() {
        return switch (cx_type.kind) {
            c.CXType_Void => @This(){ .value = .void },
            c.CXType_Bool => @This(){ .value = .bool },
            c.CXType_Char_S => @This(){ .value = .i8 },
            c.CXType_Int => @This(){ .value = .i32 },
            c.CXType_Float => @This(){ .value = .f32 },
            c.CXType_Double => @This(){ .value = .f64 },
            c.CXType_Pointer, c.CXType_LValueReference => blk: {
                const pointee_type = c.clang_getPointeeType(cx_type);
                const ptr = try allocator.create(PointerType);
                ptr.* = .{
                    .type_ref = try createFromType(allocator, pointee_type),
                };
                break :blk @This(){
                    .pointer = ptr,
                };
            },
            c.CXType_Elaborated => blk: {
                // struct
                const spelling = c.clang_getTypeSpelling(cx_type);
                defer c.clang_disposeString(spelling);
                const str = c.clang_getCString(spelling);
                const slice = std.mem.span(str);
                break :blk .{
                    .named = try allocator.dupe(u8, slice),
                };
            },
            else => {
                const str = CXString.initFromTypeKind(cx_type);
                defer str.deinit();
                std.log.warn("createFromType => {s}", .{str.toString()});
                @panic("UNKNOWN");
            },
        };
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
            .named => |name| {
                allocator.free(name);
            },
        }
    }
};
