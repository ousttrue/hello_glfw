# samples

## simple

https://www.glfw.org/docs/latest/quick_guide.html#quick_example

## sokol

https://github.com/floooh/sokol-samples/blob/master/glfw/triangle-glfw.c

> without sapp.

## imgui

https://github.com/ocornut/imgui/blob/master/examples/example_glfw_opengl3/main.cpp

### zcindex

[zcindex](./zcindex) is code generator by libclang.

> directly use mangling imgui.
> extern fn \_ZN5ImGui13CreateContextEP11ImFontAtlas(shared_font_atlas: ?*ImFontAtlas) ?*ImGuiContext;

## sokol + imgui

https://github.com/ocornut/imgui/blob/master/examples/example_glfw_opengl3/main.cpp

> without sapp.
> imgui graphics backend use sokol.

```cpp
// sokol_imgui.cpp
#define SOKOL_IMGUI_NO_SOKOL_APP
#define SOKOL_IMGUI_IMPL
#define SOKOL_GLCORE
#include <sokol_gfx.h>
#include <imgui.h>
#include <sokol_imgui.h>
```

- [imgui_sokol.zig](src/imgui_sokol.zig)
