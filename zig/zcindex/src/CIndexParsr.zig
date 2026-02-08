const std = @import("std");
const c = @import("cindex");

const DEFAULT_ARGS = [_][*:0]const u8{
    "-x",
    "c++",
    "-std=c++17",
};

const MSVC_ARGS = [_][*:0]const u8{
    "-target",
    "x86_64-windows-msvc",
    "-fdeclspec",
    "-fms-compatibility-version=18",
    "-fms-compatibility",
    "-DNOMINMAX",
};

allocator: std.mem.Allocator,
entry_point: [:0]const u8,
/// for multi headers
unsaved_file: ?c.CXUnsavedFile = null,
command_line: std.ArrayList([*:0]const u8) = .{},
include_dirs: std.ArrayList([]const u8) = .{},

flags: u32 = c.CXTranslationUnit_DetailedPreprocessingRecord | c.CXTranslationUnit_SkipFunctionBodies,

fn init(allocator: std.mem.Allocator) !@This() {
    var this = @This(){
        .allocator = allocator,
        .entry_point = undefined,
    };
    for (DEFAULT_ARGS) |arg| {
        try this.command_line.append(allocator, arg);
    }
    return this;
}

pub fn deinit(this: *@This()) void {
    if (this.unsaved_file) |unsaved_file| {
        this.allocator.free(unsaved_file.Contents[0..unsaved_file.Length]);
    }
    this.command_line.deinit(this.allocator);
    for (this.include_dirs.items) |include_dir| {
        this.allocator.free(include_dir);
    }
    this.include_dirs.deinit(this.allocator);
}

fn allocFullpathDir(allocator: std.mem.Allocator, src: [*:0]const u8) ![]const u8 {
    var realpath_buf: [1024]u8 = undefined;
    const realpath = try std.fs.cwd().realpathZ(src, &realpath_buf);
    const dir = std.fs.path.dirname(realpath).?;
    return try allocator.dupe(u8, dir);
}

pub fn fromSingleHeader(
    allocator: std.mem.Allocator,
    header: [*:0]const u8,
) !@This() {
    var this = try @This().init(allocator);

    this.entry_point = std.mem.span(header);

    const copy = try allocFullpathDir(allocator, header);
    try this.include_dirs.append(allocator, copy);

    return this;
}

/// Create a CXUnsavedFile that combines multiple #include headers
pub fn fromMultiHeadr(
    allocator: std.mem.Allocator,
    headers: []const [*:0]const u8,
) !@This() {
    var this = try @This().init(allocator);

    // make unsaved file
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    for (headers) |header| {
        const span: []const u8 = std.mem.span(header);
        try out.writer.print("#include \"{s}\"\n", .{span});

        const copy = try allocFullpathDir(allocator, header);
        try this.include_dirs.append(allocator, copy);
    }
    const contents = try out.toOwnedSlice();
    this.entry_point = "__UNSAVED_FILE__.h";
    this.unsaved_file = .{
        .Contents = &contents[0],
        .Length = contents.len,
        .Filename = this.entry_point,
    };

    return this;
}

/// Create a CXUnsavedFile with the contents.
///
/// test usage.
pub fn fromContents(
    allocator: std.mem.Allocator,
    _contents: []const u8,
) !@This() {
    // std.log.warn("contents => '{s}'", .{_contents});

    var this = try @This().init(allocator);

    // for allocator.free in deinit
    const contents: []const u8 = try allocator.dupe(u8, _contents);

    // make unsaved file
    this.entry_point = "__UNSAVED_FILE__.h";
    this.unsaved_file = .{
        .Contents = &contents[0],
        .Length = contents.len,
        .Filename = this.entry_point,
    };

    return this;
}

pub fn parse(this: *@This()) !c.CXTranslationUnit {
    const index = c.clang_createIndex(0, 0);

    std.log.warn("entry_point => {s}", .{this.entry_point});
    for (this.command_line.items, 0..) |command, i| {
        std.log.warn("[{:2}] {s}", .{ i, command });
    }

    var tu: c.CXTranslationUnit = undefined;
    const result = c.clang_parseTranslationUnit2(index,
        // entry point,
        &this.entry_point[0],
        //command_line,
        if (this.command_line.items.len > 0)
            &this.command_line.items[0]
        else
            null, @intCast(this.command_line.items.len),
        // unsaved_files,
        if (this.unsaved_file) |*unsaved_file| unsaved_file else null, if (this.unsaved_file != null) 1 else 0,
        //
        this.flags, &tu);
    switch (result) {
        c.CXError_Success => {}, // SUCCESS
        c.CXError_Failure => return error.failer,
        c.CXError_Crashed => return error.crash,
        c.CXError_InvalidArguments => return error.invalid_arguments,
        c.CXError_ASTReadError => return error.AST_read_error,
        else => unreachable,
    }
    return tu;
}
