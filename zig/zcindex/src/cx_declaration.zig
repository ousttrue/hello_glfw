const std = @import("std");
const c = @import("cindex");
const CXCursor = @import("CXCursor.zig");
const CXString = @import("CXString.zig");
const CXLocation = @import("CXLocation.zig");
const cx_util = @import("cx_util.zig");
const MAX_CHILDREN_LEN = 512;

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
    is_const: bool,

    pub fn create(
        allocator: std.mem.Allocator,
        type_ref: Type,
        is_const: bool,
    ) !*@This() {
        const this = try allocator.create(@This());
        this.* = .{
            .type_ref = type_ref,
            .is_const = is_const,
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
        offset: usize,
    };

    name: CXString,
    fields: []const Field,
    size: usize,

    pub fn create(
        allocator: std.mem.Allocator,
        name: CXString,
        fields: []const Field,
        size: usize,
    ) !*@This() {
        const this = try allocator.create(@This());
        this.* = .{
            .name = name,
            .fields = try allocator.dupe(Field, fields),
            .size = size,
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
                const name = CXString.initFromCursorSpelling(child);
                const offset: usize = switch (c.clang_Cursor_getOffsetOfField(child)) {
                    c.CXTypeLayoutError_Invalid => blk: {
                        break :blk 0;
                    },
                    c.CXTypeLayoutError_Incomplete => @panic("the field's type declaration is an incomplete type"),
                    c.CXTypeLayoutError_Dependent => @panic("the field's type declaration is a dependent type"),
                    c.CXTypeLayoutError_InvalidFieldName => @panic("the field's name S is not found"),
                    else => |s| @intCast(s),
                };
                // if (offset < 0) {
                //     @panic("offset < 0");
                // }
                fields[index] = .{
                    .name = name,
                    .type_ref = try createFromType(allocator, c.clang_getCursorType(child)),
                    .offset = @intCast(offset),
                };
                index += 1;
            }
        }

        return fields;
    }
};

pub const FunctionType = struct {
    pub const Param = struct {
        name: CXString,
        type_ref: Type,
        default: ?[]const u8 = null,

        fn init(
            allocator: std.mem.Allocator,
            src_map: *std.StringHashMap([]const u8),
            param: c.CXCursor,
            end_offset: usize,
        ) !@This() {
            const param_name = CXString.initFromCursorSpelling(param);
            var this = @This(){
                .name = param_name,
                .type_ref = try createFromType(allocator, c.clang_getCursorType(param)),
            };
            const pp = CXString.initFromPP(param);
            if (std.mem.indexOf(u8, pp.toString(), "=")) |_| {
                var buf: [32]c.CXCursor = undefined;
                const children = try cx_util.getChildren(param, &buf);
                for (children) |child| {
                    const child_kind = CXString.initFromCursorKind(child);
                    defer child_kind.deinit();
                    const child_pp = CXString.initFromCursorDisplayName(child);
                    defer child_pp.deinit();
                    const src = try getSource(allocator, src_map, child);
                    switch (child.kind) {
                        c.CXCursor_TypeRef,
                        c.CXCursor_ParmDecl,
                        => {
                            // skip
                        },
                        else => {
                            // std.log.err("{s}: {s}", .{ param_name.toString(), child_kind.toString() });
                            // const cursor_location = CXLocation.init(_cursor);
                            const child_location = CXLocation.init(child);
                            // CXLocation.init(_cursor).end.offset;
                            // search next ')'
                            // var x = child_location.end.offset;
                            // while (x < src.len) : (x += 1) {
                            //     if (src[x] == ')' or src[x] == ',') {
                            //         break;
                            //     }
                            // }
                            // try this.writer.print("  [{s}] => '{s}'\n", .{
                            //     child_kind.toString(),
                            //     src[child_location.start.offset..x],
                            // });
                            var default = src[child_location.start.offset..end_offset];
                            default = std.mem.trim(u8, default, &std.ascii.whitespace);
                            if (std.mem.endsWith(u8, default, ",")) {
                                default = default[0 .. default.len - 1];
                            }
                            if (default[0] == '=') {
                                default = default[1..];
                            }
                            default = std.mem.trim(u8, default, &std.ascii.whitespace);
                            this.default = default;

                            break;
                        },
                    }
                }
            }
            return this;
        }

        const MATCH: []const []const u8 = &.{ "type", "c" };
        const REPLACE: []const []const u8 = &.{ "_type", "_c" };

        pub fn getName(this: @This()) []const u8 {
            const name = this.name.toString();
            for (MATCH, REPLACE) |m, r| {
                if (std.mem.eql(u8, name, m)) {
                    return r;
                }
            }
            return name;
        }

        fn getSource(allocator: std.mem.Allocator, src_map: *std.StringHashMap([]const u8), cursor: c.CXCursor) ![]const u8 {
            const file = CXString.initFromCursorFilepath(cursor);
            defer file.deinit();
            const path = file.toString();
            if (src_map.get(path)) |src| {
                return src;
            } else {
                const src = try std.fs.cwd().readFileAllocOptions(
                    allocator,
                    path,
                    std.math.maxInt(u32),
                    null,
                    .@"1",
                    null,
                );
                try src_map.put(path, src);
                return src;
            }
        }
    };

    name: CXString,
    mangling: CXString,
    ret_type: Type,
    params: []Param,
    is_variadic: bool,

    pub fn create(
        allocator: std.mem.Allocator,
        cursor: c.CXCursor,
        src_map: *std.StringHashMap([]const u8),
        name: CXString,
        mangling: CXString,
        ret_type: Type,
        params: []const c.CXCursor,
        is_variadic: bool,
    ) !*@This() {
        var this = try allocator.create(@This());
        this.* = .{
            .name = name,
            .mangling = mangling,
            .ret_type = ret_type,
            .params = try allocator.alloc(Param, params.len),
            .is_variadic = is_variadic,
        };
        for (params, 0..) |param, i| {
            const end_offset = if (i + 1 < params.len)
                CXLocation.init(params[i + 1]).start.offset
            else
                CXLocation.init(cursor).end.offset - 1;
            this.params[i] = try Param.init(allocator, src_map, param, end_offset);
        }
        return this;
    }

    pub fn destroy(this: *const @This(), allocator: std.mem.Allocator) void {
        this.ret_type.destroy(allocator);
        for (this.params) |*param| {
            param.name.deinit();
            param.type_ref.destroy(allocator);
        }
        allocator.free(this.params);
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

    pub fn createFromCursor(
        allocator: std.mem.Allocator,
        src_map: *std.StringHashMap([]const u8),
        cursor: c.CXCursor,
    ) !?@This() {
        return switch (cursor.kind) {
            c.CXCursor_TypedefDecl => .{
                .typedef = try TypedefType.create(
                    allocator,
                    CXString.initFromCursorSpelling(cursor),
                    try createFromType(allocator, c.clang_getTypedefDeclUnderlyingType(cursor)),
                ),
            },
            //
            c.CXCursor_StructDecl => blk: {
                const name = CXString.initFromCursorSpelling(cursor);
                var buf: [MAX_CHILDREN_LEN]c.CXCursor = undefined;
                const children = try cx_util.getChildren(cursor, &buf);
                const fields = try ContainerType.getFields(allocator, children);
                defer allocator.free(fields);
                const size: usize = switch (c.clang_Type_getSizeOf(c.clang_getCursorType(cursor))) {
                    c.CXTypeLayoutError_Invalid => @panic("Type is of kind CXType_Invalid."),
                    c.CXTypeLayoutError_Incomplete => 0, //@panic("The type is an incomplete Type."),
                    c.CXTypeLayoutError_Dependent => @panic("The type is a dependent Type."),
                    c.CXTypeLayoutError_NotConstantSize => @panic("The type is not a constant size type."),
                    c.CXTypeLayoutError_InvalidFieldName => @panic("The Field name is not valid for this record."),
                    c.CXTypeLayoutError_Undeduced => @panic("The type is undeduced."),
                    else => |s| @intCast(s),
                };
                break :blk .{
                    .container = try ContainerType.create(
                        allocator,
                        name,
                        fields,
                        @intCast(size),
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
                var buf: [MAX_CHILDREN_LEN]c.CXCursor = undefined;
                const children = try cx_util.getChildren(cursor, &buf);
                const values = try EnumType.getValues(allocator, children);
                defer allocator.free(values);
                break :blk .{
                    .int_enum = try EnumType.create(
                        allocator,
                        CXString.initFromCursorSpelling(cursor),
                        values,
                    ),
                };
            },
            c.CXCursor_EnumConstantDecl => null,
            //
            c.CXCursor_FunctionDecl => blk: {
                var buf: [MAX_CHILDREN_LEN]c.CXCursor = undefined;
                // const children = try cx_util.getChildren(cursor, &buf);
                const param_count: usize = @intCast(c.clang_Cursor_getNumArguments(cursor));
                var params = buf[0..param_count];
                for (0..param_count) |i| {
                    params[i] = c.clang_Cursor_getArgument(cursor, @intCast(i));
                }
                break :blk .{
                    .function = try FunctionType.create(
                        allocator,
                        cursor,
                        src_map,
                        CXString.initFromCursorSpelling(cursor),
                        CXString.initFromMangling(cursor),
                        try createFromType(allocator, c.clang_getCursorResultType(cursor)),
                        params,
                        c.clang_isFunctionTypeVariadic(c.clang_getCursorType(cursor)) != 0,
                    ),
                };
            },
            c.CXCursor_ParmDecl => null,
            //
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
            c.CXCursor_TypeRef,
            c.CXCursor_UnexposedAttr,
            c.CXCursor_MemberRef,
            c.CXCursor_FloatingLiteral,
            c.CXCursor_CompoundStmt,
            c.CXCursor_UnexposedExpr,
            c.CXCursor_DeclRefExpr,
            c.CXCursor_IntegerLiteral,
            c.CXCursor_CallExpr,
            c.CXCursor_UnaryOperator,
            c.CXCursor_StringLiteral,
            c.CXCursor_CXXBoolLiteralExpr,
            c.CXCursor_UnaryExpr,
            c.CXCursor_BinaryOperator,
            c.CXCursor_TemplateTypeParameter,
            => null,
            else => {
                const str = CXString.initFromCursorKind(cursor);
                defer str.deinit();
                std.log.err("cursor.type [{s} = {}]", .{ str.toString(), cursor.kind });
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
                .is_const = c.clang_isConstQualifiedType(pointee_type) != 0,
            };
            break :blk Type{
                .pointer = ptr,
            };
        },
        c.CXType_IncompleteArray => blk: {
            const array_type = c.clang_getArrayElementType(cx_type);
            const ptr = try allocator.create(PointerType);
            ptr.* = .{
                .type_ref = try createFromType(allocator, array_type),
                .is_const = c.clang_isConstQualifiedType(array_type) != 0,
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
