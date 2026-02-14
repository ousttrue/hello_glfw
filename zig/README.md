# simple

https://www.glfw.org/docs/latest/quick_guide.html#quick_example

# sokol

https://github.com/floooh/sokol-samples/blob/master/glfw/triangle-glfw.c

> without sapp.

# imgui

https://github.com/ocornut/imgui/blob/master/examples/example_glfw_opengl3/main.cpp

## zcindex

[zcindex](./zcindex) is code generator by libclang.

> directly use mangling imgui.
> extern fn \_ZN5ImGui13CreateContextEP11ImFontAtlas(shared_font_atlas: ?*ImFontAtlas) ?*ImGuiContext;

# sokol + imgui

https://github.com/ocornut/imgui/blob/master/examples/example_glfw_opengl3/main.cpp

> graphics backend to sokol

## sokol_imgui mod

https://github.com/floooh/sokol-zig/blob/master/src/sokol/c/sokol_imgui.h

- sapp => glfw
- cimgui => mangling-imgui (zcindex)
  - `ImGui_ImplSokol_Init`
  - `ImGui_ImplSokol_Shutdown`
  - `ImGui_ImplSokol_NewFrame`
  - `ImGui_ImplSokol_RenderDrawData`
