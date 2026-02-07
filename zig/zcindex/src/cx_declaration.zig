const std = @import("std");
const c = @import("cindex");
const CXCursor = @import("CXCursor.zig");
const CXString = @import("CXString.zig");

pub const ValueType = union(enum) {
    void,
    bool,
    u8,
    u16,
    u32,
    u64,
    i8,
    i16,
    i32,
    i64,
    f32,
    f64,
};

pub const TypedefType = struct {
    name: CXString,
    type_ref: Type,

    pub fn create(
        allocator: std.mem.Allocator,
        name: CXString,
        type_ref: Type,
    ) !*@This() {
        const this = try allocator.create(@This());
        this.* = .{
            .name = name,
            .type_ref = type_ref,
        };
        return this;
    }

    pub fn destroy(this: *const @This(), allocator: std.mem.Allocator) void {
        this.name.deinit();
        this.type_ref.destroy(allocator);
        allocator.destroy(this);
    }
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

pub const ArrayType = struct {
    type_ref: Type,
    len: usize,

    pub fn create(
        allocator: std.mem.Allocator,
        type_ref: Type,
        len: usize,
    ) !*@This() {
        const this = try allocator.create(@This());
        this.* = .{
            .type_ref = type_ref,
            .len = len,
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
        name: CXString,
        type_ref: Type,
    };

    name: CXString,
    fields: []const Field,

    pub fn create(
        allocator: std.mem.Allocator,
        name: CXString,
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
            field.name.deinit();
            field.type_ref.destroy(allocator);
        }
        allocator.free(this.fields);
        this.name.deinit();
        allocator.destroy(this);
    }

    pub fn getFields(allocator: std.mem.Allocator, children: []c.CXCursor) ![]Field {
        var index: usize = 0;
        for (children) |child| {
            if (child.kind == c.CXCursor_FieldDecl) {
                index += 1;
            }
        }
        var fields = try allocator.alloc(Field, index);

        index = 0;
        for (children) |child| {
            if (child.kind == c.CXCursor_FieldDecl) {
                fields[index] = .{
                    .name = CXString.initFromCursorSpelling(child),
                    .type_ref = try createFromType(allocator, c.clang_getCursorType(child)),
                };
                index += 1;
            }
        }

        return fields;
    }
};

pub const FunctionType = struct {
    pub const Param = struct {
        name: []const u8,
        type_ref: Type,
    };

    name: CXString,
    mangling: CXString,
    ret_type: Type,
    params: []const Param,

    pub fn create(
        allocator: std.mem.Allocator,
        name: CXString,
        mangling: CXString,
        ret_type: Type,
        params: []const Param,
    ) !*@This() {
        const this = try allocator.create(@This());
        this.* = .{
            .name = name,
            .mangling = mangling,
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
        this.name.deinit();
        allocator.destroy(this);
    }
};

pub const EnumType = struct {
    pub const Value = struct {
        name: CXString,
        value: i64,
    };

    name: CXString,
    values: []const Value,

    pub fn create(
        allocator: std.mem.Allocator,
        name: CXString,
        values: []const Value,
    ) !*@This() {
        const this = try allocator.create(@This());
        this.* = .{
            .name = name,
            .values = try allocator.dupe(Value, values),
        };
        return this;
    }

    pub fn destroy(this: *const @This(), allocator: std.mem.Allocator) void {
        for (this.values) |value| {
            value.name.deinit();
        }
        allocator.free(this.values);
        this.name.deinit();
        allocator.destroy(this);
    }

    pub fn getValues(allocator: std.mem.Allocator, children: []c.CXCursor) ![]Value {
        var index: usize = 0;
        for (children) |child| {
            if (child.kind == c.CXCursor_EnumConstantDecl) {
                index += 1;
            }
        }
        var values = try allocator.alloc(Value, index);

        index = 0;
        for (children) |child| {
            if (child.kind == c.CXCursor_EnumConstantDecl) {
                values[index] = .{
                    .name = CXString.initFromCursorSpelling(child),
                    .value = c.clang_getEnumConstantDeclValue(child),
                };
                index += 1;
            }
        }

        return values;
    }
};

pub const Type = union(enum) {
    value: ValueType,
    typedef: *TypedefType,
    pointer: *PointerType,
    array: *ArrayType,
    container: *ContainerType,
    function: *FunctionType,
    int_enum: *EnumType,
    named: CXString,

    pub fn createFromCursor(allocator: std.mem.Allocator, cursor: CXCursor) !?@This() {
        return switch (cursor.cursor.kind) {
            c.CXCursor_StructDecl => blk: {
                const fields = try ContainerType.getFields(allocator, cursor.children.items);
                defer allocator.free(fields);
                break :blk .{
                    .container = try ContainerType.create(
                        allocator,
                        CXString.initFromCursorSpelling(cursor.cursor),
                        fields,
                    ),
                };
            },
            c.CXCursor_FieldDecl => null,
            //
            c.CXCursor_EnumDecl => blk: {
                // TODO
                // break :blk .{
                //     .typedef = try TypedefType.create(
                //         allocator,
                //         cursor.getSpelling(),
                //         .{ .value = .i32 },
                //     ),
                // };
                const values = try EnumType.getValues(allocator, cursor.children.items);
                defer allocator.free(values);
                break :blk .{
                    .int_enum = try EnumType.create(
                        allocator,
                        CXString.initFromCursorSpelling(cursor.cursor),
                        values,
                    ),
                };
            },
            c.CXCursor_EnumConstantDecl => null,
            //
            c.CXCursor_TypedefDecl => .{
                .typedef = try TypedefType.create(
                    allocator,
                    CXString.initFromCursorSpelling(cursor.cursor),
                    try createFromType(allocator, c.clang_getTypedefDeclUnderlyingType(cursor.cursor)),
                ),
            },
            //
            c.CXCursor_FunctionDecl => .{
                .function = try FunctionType.create(
                    allocator,
                    CXString.initFromCursorSpelling(cursor.cursor),
                    CXString.initFromMangling(cursor.cursor),
                    try createFromType(allocator, c.clang_getCursorResultType(cursor.cursor)),
                    &.{},
                ),
            },
            c.CXCursor_MacroDefinition,
            c.CXCursor_MacroExpansion,
            c.CXCursor_InclusionDirective,
            c.CXCursor_FunctionTemplate,
            c.CXCursor_ClassTemplate,
            c.CXCursor_CXXMethod,
            c.CXCursor_Constructor,
            c.CXCursor_Destructor,
            c.CXCursor_ConversionFunction,
            c.CXCursor_VarDecl,
            c.CXCursor_UnionDecl,
            c.CXCursor_Namespace,
            => null,
            else => {
                const str = CXString.initFromCursorKind(cursor.cursor);
                defer str.deinit();
                std.log.warn("cursor.type [{s} = {}]", .{ str.toString(), cursor.cursor.kind });
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
            .array => |array| {
                array.destroy(allocator);
            },
            .typedef => |typedef| {
                typedef.destroy(allocator);
            },
            .container => |container| {
                container.destroy(allocator);
            },
            .function => |function| {
                function.destroy(allocator);
            },
            .int_enum => |int_enum| {
                int_enum.destroy(allocator);
            },
            .named => |name| {
                name.deinit();
            },
        }
    }
};

// https://clang.llvm.org/docs/LibClang.html
// https://github.com/ousttrue/luajitffi/blob/master/clangffi/types.lua
fn createFromType(allocator: std.mem.Allocator, cx_type: c.CXType) !Type {
    return switch (cx_type.kind) {
        c.CXType_Void => Type{ .value = .void },
        c.CXType_Bool => Type{ .value = .bool },
        c.CXType_Char_S, c.CXType_SChar => Type{ .value = .i8 },
        c.CXType_Short => Type{ .value = .i16 },
        c.CXType_Int => Type{ .value = .i32 },
        c.CXType_LongLong => Type{ .value = .i64 },
        c.CXType_UChar => Type{ .value = .u8 },
        c.CXType_UShort => Type{ .value = .u16 },
        c.CXType_UInt => Type{ .value = .u32 },
        c.CXType_ULongLong => Type{ .value = .u64 },
        c.CXType_Float => Type{ .value = .f32 },
        c.CXType_Double => Type{ .value = .f64 },
        c.CXType_Pointer, c.CXType_LValueReference => blk: {
            const pointee_type = c.clang_getPointeeType(cx_type);
            const ptr = try allocator.create(PointerType);
            ptr.* = .{
                .type_ref = try createFromType(allocator, pointee_type),
            };
            break :blk Type{
                .pointer = ptr,
            };
        },
        c.CXType_ConstantArray => blk: {
            const array_type = c.clang_getArrayElementType(cx_type);
            const len: usize = @intCast(c.clang_getArraySize(cx_type));
            const array = try allocator.create(ArrayType);
            array.* = .{
                .type_ref = try createFromType(allocator, array_type),
                .len = len,
            };
            break :blk Type{
                .array = array,
            };
        },
        c.CXType_FunctionProto => blk: {
            // const ptr = try allocator.create(PointerType);
            // ptr.* = .{
            //     .type_ref = .{ .value = .void },
            // };
            // break :blk Type{
            //     .pointer = ptr,
            // };
            break :blk .{ .value = .void };
        },
        c.CXType_Elaborated => blk: {
            // struct
            const spelling = CXString.initFromTypeSpelling(cx_type);
            break :blk .{
                .named = spelling,
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
