const imgui = @import("imgui");

pub fn ImGui_ImplSokol_Init(opts: struct {}) void {
    _ = opts;
}

pub fn ImGui_ImplSokol_Shutdown() void {
}

pub fn ImGui_ImplSokol_NewFrame() void {
}

pub fn ImGui_ImplSokol_RenderDrawData(raw_data: ?*imgui.ImDrawData) void {
    _ = raw_data;
}
