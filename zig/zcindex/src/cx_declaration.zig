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
    name: []const u8,
    type_ref: Type,

    pub fn create(
        allocator: std.mem.Allocator,
        name: []const u8,
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
        var new_fields = try allocator.alloc(Field, fields.len);
        for (fields, 0..) |field, i| {
            new_fields[i] = .{
                .name = try allocator.dupe(u8, field.name),
                .type_ref = field.type_ref,
            };
        }
        const this = try allocator.create(@This());
        this.* = .{
            .name = name,
            .fields = new_fields,
        };
        return this;
    }

    pub fn destroy(this: *const @This(), allocator: std.mem.Allocator) void {
        for (this.fields) |*field| {
            allocator.free(field.name);
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
    typedef: *TypedefType,
    pointer: *PointerType,
    array: *ArrayType,
    container: *ContainerType,
    function: *FunctionType,
    int_enum: *EnumType,
    named: []const u8,

    pub fn createFromCursor(allocator: std.mem.Allocator, cursor: CXCursor) !?@This() {
        return switch (cursor.cursor.kind) {
            c.CXCursor_StructDecl => blk: {
                var field_index: usize = 0;
                for (cursor.children.items) |child| {
                    if (child.kind == c.CXCursor_FieldDecl) {
                        field_index += 1;
                    }
                }
                const fields = try allocator.alloc(ContainerType.Field, field_index);
                defer allocator.free(fields);
                field_index = 0;
                for (cursor.children.items) |child| {
                    if (child.kind == c.CXCursor_FieldDecl) {
                        const spelling = CXString.initFromCursorSpelling(child);
                        defer spelling.deinit();
                        fields[field_index] = .{
                            .name = try allocator.dupe(u8, spelling.toString()),
                            .type_ref = try createFromType(allocator, c.clang_getCursorType(child)),
                        };
                        field_index += 1;
                    }
                }
                defer {
                    for (fields) |field| {
                        allocator.free(field.name);
                    }
                }
                break :blk .{
                    .container = try ContainerType.create(
                        allocator,
                        cursor.getSpelling(),
                        fields,
                    ),
                };
            },
            c.CXCursor_FieldDecl => null,
            c.CXCursor_TypedefDecl => .{
                .typedef = try TypedefType.create(
                    allocator,
                    cursor.getSpelling(),
                    try createFromType(allocator, c.clang_getTypedefDeclUnderlyingType(cursor.cursor)),
                ),
            },
            c.CXCursor_EnumDecl => blk: {
                // TODO
                break :blk .{
                    .typedef = try TypedefType.create(
                        allocator,
                        cursor.getSpelling(),
                        .{ .value = .i32 },
                    ),
                };
            },
            c.CXCursor_FunctionDecl => .{
                .function = try FunctionType.create(
                    allocator,
                    cursor.getSpelling(),
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

    // https://clang.llvm.org/docs/LibClang.html
    // https://github.com/ousttrue/luajitffi/blob/master/clangffi/types.lua
    pub fn createFromType(allocator: std.mem.Allocator, cx_type: c.CXType) !@This() {
        return switch (cx_type.kind) {
            c.CXType_Void => @This(){ .value = .void },
            c.CXType_Bool => @This(){ .value = .bool },
            c.CXType_Char_S, c.CXType_SChar => @This(){ .value = .i8 },
            c.CXType_Short => @This(){ .value = .i16 },
            c.CXType_Int => @This(){ .value = .i32 },
            c.CXType_LongLong => @This(){ .value = .i64 },
            c.CXType_UChar => @This(){ .value = .u8 },
            c.CXType_UShort => @This(){ .value = .u16 },
            c.CXType_UInt => @This(){ .value = .u32 },
            c.CXType_ULongLong => @This(){ .value = .u64 },
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
            c.CXType_ConstantArray => blk: {
                const array_type = c.clang_getArrayElementType(cx_type);
                const len: usize = @intCast(c.clang_getArraySize(cx_type));
                const array = try allocator.create(ArrayType);
                array.* = .{
                    .type_ref = try createFromType(allocator, array_type),
                    .len = len,
                };
                break :blk @This(){
                    .array = array,
                };
            },
            c.CXType_FunctionProto => blk: {
                // const ptr = try allocator.create(PointerType);
                // ptr.* = .{
                //     .type_ref = .{ .value = .void },
                // };
                // break :blk @This(){
                //     .pointer = ptr,
                // };
                break :blk .{ .value = .void };
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
            .int_enum => {
                @panic("not impl");
            },
            .named => |name| {
                allocator.free(name);
            },
        }
    }
};
