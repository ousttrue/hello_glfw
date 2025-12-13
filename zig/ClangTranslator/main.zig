// https://rocm.docs.amd.com/projects/llvm-project/en/latest/LLVM/clang/html/LibClang.html

const std = @import("std");
const c = @import("clang");
const CIndexParser = @import("CIndexParsr.zig");
const CXCursor = @import("CXCursor.zig");
const CXString = @import("CXString.zig");

pub fn main() !void {
    if (std.os.argv.len < 2) {
        return error.no_commandline_arg;
    }

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.detectLeaks();
    const allocator = gpa.allocator();

    var writer_buf: [1024]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&writer_buf);
    defer writer.interface.flush() catch @panic("OOM");

    var cindex_parser = if (std.os.argv.len == 2)
        try CIndexParser.fromSingleHeader(allocator, std.os.argv[1])
    else
        try CIndexParser.fromMultiHeadr(allocator, std.os.argv[1..]);
    defer cindex_parser.deinit();

    const tu = try cindex_parser.parse();
    defer c.clang_disposeTranslationUnit(tu);

    var data = ClientData.init(
        allocator,
        &writer.interface,
        cindex_parser.entry_point,
        cindex_parser.include_dirs.items,
    );
    defer data.deinit();

    _ = c.clang_visitChildren(
        c.clang_getTranslationUnitCursor(tu),
        ClientData.Visitor,
        &data,
    );
}

const ClientData = struct {
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    include_dirs: []const []const u8,
    entry_point: []const u8,
    i: u32 = 0,
    name_count: std.StringHashMap(u32),

    export fn Visitor(
        cursor: c.CXCursor,
        parent: c.CXCursor,
        client_data: c.CXClientData,
    ) c.CXChildVisitResult {
        const data: *@This() = @ptrCast(@alignCast(client_data));
        return data.onVisit(cursor, parent) catch {
            return c.CXChildVisit_Break;
        };
    }

    fn init(
        allocator: std.mem.Allocator,
        writer: *std.Io.Writer,
        entry_point: []const u8,
        include_dirs: []const []const u8,
    ) @This() {
        return .{
            .allocator = allocator,
            .writer = writer,
            .include_dirs = include_dirs,
            .entry_point = entry_point,
            .name_count = .init(allocator),
        };
    }

    fn deinit(this: *@This()) void {
        var it = this.name_count.keyIterator();
        while (it.next()) |key| {
            this.allocator.free(key.*);
        }
        this.name_count.deinit();
    }

    fn onVisit(
        this: *@This(),
        _cursor: c.CXCursor,
        _parent: c.CXCursor,
    ) !c.CXChildVisitResult {
        var cursor = CXCursor.init(_cursor);
        defer cursor.deinit();

        var parent = CXCursor.init(_parent);
        defer parent.deinit();

        const loc = cursor.getLocation();
        _ = loc;
        if (!this.isAcceptable(cursor)) {
            // skip
            return c.CXVisit_Continue;
        }

        var decl = Decl.init(_cursor);
        defer decl.deinit();
        switch (decl) {
            .function => |func| {
                const name = try this.allocator.dupe(u8, func.name.toString());

                const kv = try this.name_count.getOrPut(name);
                if (kv.found_existing) {
                    defer this.allocator.free(name);
                    defer kv.value_ptr.* += 1;
                } else {
                    defer kv.value_ptr.* = 1;

                    if (std.mem.startsWith(u8, name, "operator ")) {} else {
                        // skip
                        try this.writer.print("extern fn {s}() {s};\n", .{
                            func.mangling.toString(),
                            func.ret_type.toString(),
                        });
                        try this.writer.print("pub const {s} = {s};\n", .{
                            func.name.toString(),
                            func.mangling.toString(),
                        });
                    }
                }
            },
            .none => {},
        }

        switch (cursor.cursor.kind) {
            c.CXCursor_MacroExpansion => {
                // skip
            },
            else => {
                // std.log.debug("[{:03}] {s}:{}:{} => <{s}(0x{x})> <{s}(0x{x})> {s}", .{
                //     this.i,
                //     std.fs.path.basename(loc.path),
                //     loc.line,
                //     loc.col,
                //     // parent
                //     parent.kindName(),
                //     c.clang_hashCursor(parent.cursor),
                //     // cursor
                //     cursor.kindName(),
                //     c.clang_hashCursor(cursor.cursor),
                //     cursor.getDisplay(),
                // });
                this.i += 1;
            },
        }

        return switch (cursor.cursor.kind) {
            c.CXCursor_Namespace => c.CXChildVisit_Recurse,
            else => c.CXChildVisit_Continue,
        };
    }

    fn isAcceptable(this: @This(), cursor: CXCursor) bool {
        if (c.clang_getCString(cursor.filename)) |p| {
            const cursor_path = std.mem.span(p);
            // if (std.mem.eql(u8, cursor_path, this.entry_point)) {
            //     return true;
            // }
            for (this.include_dirs) |include| {
                if (std.mem.startsWith(u8, cursor_path, include)) {
                    return true;
                }
            }
        }

        return false;
    }
};

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

const Decl = union(enum) {
    none,
    function: DeclFunction,

    fn init(cursor: c.CXCursor) @This() {
        return switch (cursor.kind) {
            c.CXCursor_FunctionDecl => .{ .function = DeclFunction.init(cursor) },
            else => .{ .none = void{} },
        };
    }

    fn deinit(this: *@This()) void {
        switch (this.*) {
            .function => |*f| {
                f.deinit();
            },
            .none => {},
        }
    }
};

test "cindex" {
    try std.testing.expect(false);
}
