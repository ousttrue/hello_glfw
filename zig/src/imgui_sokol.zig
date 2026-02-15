const imgui = @import("imgui");
const sokol = @import("sokol");
// const c = @cImport({
//     @cDefine("SOKOL_IMGUI_NO_SOKOL_APP", "1");
//     @cInclude("sokol_gfx.h");
//     @cInclude("imgui.h"); // error: because of the c++ element
//     @cInclude("sokol_imgui.h");
// });

pub const simgui_allocator_t = extern struct {
    alloc_fn: ?*const fn (size: usize, user_data: ?*anyopaque) *anyopaque = null,
    free_fn: ?*const fn (ptr: *anyopaque, user_data: ?*anyopaque) void = null,
    user_data: ?*anyopaque = null,
};

pub const simgui_logger_t = extern struct {
    func: ?*const fn (
        tag: [*c]const u8, // always "simgui"
        log_level: u32, // 0=panic, 1=error, 2=warning, 3=info
        log_item_id: u32, // SIMGUI_LOGITEM_*
        message_or_null: [*c]const u8, // a message string, may be nullptr in release mode
        line_nr: u32, // line number in sokol_imgui.h
        filename_or_null: [*c]const u8, // source filename, may be nullptr in release mode
        user_data: ?*anyopaque,
    ) void = null,
    user_data: ?*anyopaque = null,
};

pub const simgui_desc_t = extern struct {
    max_vertices: i32 = 0, // default: 65536
    color_format: sokol.gfx.PixelFormat = .DEFAULT,
    depth_format: sokol.gfx.PixelFormat = .DEFAULT,
    sample_count: i32 = 0,
    ini_filename: [*c]const u8 = null,
    no_default_font: bool = false,
    disable_paste_override: bool = false, // if true, don't send Ctrl-V on EVENTTYPE_CLIPBOARD_PASTED
    disable_set_mouse_cursor: bool = false, // if true, don't control the mouse cursor type via sapp_set_mouse_cursor()
    disable_windows_resize_from_edges: bool = false, // if true, only resize edges from the bottom right corner
    write_alpha_channel: bool = false, // if true, alpha values get written into the framebuffer
    allocator: simgui_allocator_t = .{}, // optional memory allocation overrides (default: malloc/free)
    logger: simgui_logger_t = .{}, // optional log function override
};

extern fn simgui_setup(desc: *const simgui_desc_t) void;
pub fn ImGui_ImplSokol_Init(desc: *const simgui_desc_t) void {
    simgui_setup(desc);
}

extern fn simgui_shutdown() void;
pub fn ImGui_ImplSokol_Shutdown() void {
    simgui_shutdown();
}

// pub fn ImGui_ImplSokol_NewFrame() void {
// }

extern fn simgui_render() void;
pub fn ImGui_ImplSokol_RenderDrawData(raw_data: ?*imgui.ImDrawData) void {
    _ = raw_data;
    simgui_render();
}
