const std = @import("std");
const c = @import("cindex");
const CXCursor = @import("CXCursor.zig");
const CXString = @import("CXString.zig");

allocator: std.mem.Allocator,
entry_point: []const u8,
include_dirs: []const []const u8,
cursors: std.ArrayList(CXCursor) = .{},

pub fn init(
    allocator: std.mem.Allocator,
    entry_point: []const u8,
    include_dirs: []const []const u8,
) @This() {
    return .{
        .allocator = allocator,
        .include_dirs = include_dirs,
        .entry_point = entry_point,
    };
}

pub fn deinit(this: *@This()) void {
    for (this.cursors.items) |*item| {
        item.children.deinit(this.allocator);
    }
    this.cursors.deinit(this.allocator);
}

pub export fn ClientData_visitor(
    cursor: c.CXCursor,
    parent: c.CXCursor,
    client_data: c.CXClientData,
) c.CXChildVisitResult {
    const data: *@This() = @ptrCast(@alignCast(client_data));
    return data.onVisit(cursor, parent) catch {
        return c.CXChildVisit_Break;
    };
}


pub fn getCursorByName(this: @This(), name: []const u8) ?CXCursor {
    for (this.cursors.items) |item| {
        const spelling = CXString.initFromCursorSpelling(item.cursor);
        defer spelling.deinit();
        if (std.mem.eql(u8, spelling.toString(), name)) {
            return item;
        }
    }
    return null;
}

fn onVisit(
    this: *@This(),
    _cursor: c.CXCursor,
    _parent: c.CXCursor,
) !c.CXChildVisitResult {
    const cursor = CXCursor.init(_cursor, _parent);
    if (!this.isAcceptable(cursor)) {
        // skip
        return c.CXVisit_Continue;
    }
    try this.cursors.append(this.allocator, cursor);

    for (this.cursors.items) |*item| {
        if (c.clang_equalCursors(item.cursor, _parent) != 0) {
            // parent found
            try item.children.append(this.allocator, _cursor);
            break;
        }
    }

    return switch (cursor.cursor.kind) {
        c.CXCursor_Namespace => c.CXChildVisit_Recurse,
        c.CXCursor_StructDecl => c.CXChildVisit_Recurse,
        c.CXCursor_EnumDecl => c.CXChildVisit_Recurse,
        c.CXCursor_FunctionDecl => c.CXChildVisit_Recurse,
        else => c.CXChildVisit_Continue,
    };
}

fn isAcceptable(this: @This(), cursor: CXCursor) bool {
    if (cursor.isFromMainFile()) {
        return true;
    }

    const filename = CXString.initFromCursorFilepath(cursor.cursor);
    defer filename.deinit();

    // if (c.clang_getCString(cursor.filename)) |p| {
    {
        const cursor_path = filename.toString();
        // std.log.debug("{s}, {s}", .{ this.entry_point, cursor_path });
        if (std.mem.eql(u8, cursor_path, this.entry_point)) {
            return true;
        }
        for (this.include_dirs) |include| {
            if (std.mem.startsWith(u8, cursor_path, include)) {
                return true;
            }
        }
    }

    return false;
}

const CXType = struct {
    cxtype: c.CXType,

    fn init(cxtype: c.CXType) @This() {
        return .{
            .cxtype = cxtype,
        };
    }

    fn deinit(this: @This()) void {
        _ = this;
    }

    fn toString(this: @This()) []const u8 {
        return switch (this.cxtype.kind) {
            c.CXType_Void => "void",
            c.CXType_Bool => "bool",
            c.CXType_Float => "f32",
            c.CXType_Double => "f64",
            c.CXType_Int => "c_int",
            c.CXType_Pointer => "*opaque {}",
            c.CXType_LValueReference => "*opaque {}",
            c.CXType_Elaborated => "opaque {}",
            else => std.fmt.bufPrint(&tmp, "CXType_({})", .{this.cxtype.kind}) catch @panic("OOM"),
        };
    }
};

var tmp: [256]u8 = undefined;

const DeclFunction = struct {
    name: CXString,
    mangling: CXString,

    ret_type: CXType,

    fn init(cursor: c.CXCursor) @This() {
        return .{
            .name = .init(c.clang_getCursorSpelling(cursor)),
            .mangling = .init(c.clang_Cursor_getMangling(cursor)),
            .ret_type = .init(c.clang_getCursorResultType(cursor)),
        };
    }

    fn deinit(this: *@This()) void {
        this.ret_type.deinit();
        this.mangling.deinit();
        this.name.deinit();
    }
};
