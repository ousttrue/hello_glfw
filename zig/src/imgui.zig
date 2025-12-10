// https://github.com/ocornut/imgui/blob/master/examples/example_glfw_opengl3/main.cpp
// Dear ImGui: standalone example application for GLFW + OpenGL 3, using programmable pipeline
// (GLFW is a cross-platform general purpose library for handling windows, inputs, OpenGL/Vulkan/Metal graphics context creation, etc.)

// Learn about Dear ImGui:
// - FAQ                  https://dearimgui.com/faq
// - Getting Started      https://dearimgui.com/getting-started
// - Documentation        https://dearimgui.com/docs (same as your local docs/ folder).
// - Introduction, links and more at the top of imgui.cpp

const std = @import("std");
const glfw = @import("glfw");
const gl = @import("glad");
const linmath = @import("linmath.zig");

// #include "imgui.h"
// #include "imgui_impl_glfw.h"
// #include "imgui_impl_opengl3.h"
// #include <stdio.h>
// #define GL_SILENCE_DEPRECATION
// #if defined(IMGUI_IMPL_OPENGL_ES2)
// #include <GLES2/gl2.h>
// #endif
// #include <GLFW/glfw3.h> // Will drag system OpenGL headers
//
// // [Win32] Our example includes a copy of glfw3.lib pre-compiled with VS2010 to maximize ease of testing and compatibility with old VS compilers.
// // To link with VS2010-era libraries, VS2015+ requires linking with legacy_stdio_definitions.lib, which we do using this pragma.
// // Your own project should not be affected, as you are likely to link with a newer binary of GLFW that is adequate for your version of Visual Studio.
// #if defined(_MSC_VER) && (_MSC_VER >= 1900) && !defined(IMGUI_DISABLE_WIN32_FUNCTIONS)
// #pragma comment(lib, "legacy_stdio_definitions")
// #endif
//
// // This example can also compile and run with Emscripten! See 'Makefile.emscripten' for details.
// #ifdef __EMSCRIPTEN__
// #include "../libs/emscripten/emscripten_mainloop_stub.h"
// #endif

export fn glfw_error_callback(err: c_int, description: [*c]const u8) void {
    std.debug.print("GLFW Error {}: {s}\n", .{ err, description });
}

extern fn c_ig_CHECKVERSION() void;
extern fn c_ig_CreateContext() void;
const ImGuiIO = opaque {};
extern fn c_ig_GetIO() *ImGuiIO;
extern fn c_ig_NewFrame() void;
extern fn c_ig_ShowDemoWindow(show_demo_window: ?*bool) void;
extern fn c_ig_Render() void;
const ImDrawData = opaque {};
extern fn c_ig_GetDrawData() *ImDrawData;

// backend
extern fn c_ImplOpenGL3_Init(glsl_version: [*c]const u8) bool;
extern fn c_ImplOpenGL3_NewFrame() void;
extern fn c_ImplGlfw_NewFrame() void;
extern fn c_ImplOpenGL3_RenderDrawData(data: *ImDrawData) void;

extern fn c_ImplGlfw_GetContentScaleForMonitor(monitor: ?*glfw.GLFWmonitor) f32;
extern fn c_ImplGlfw_InitForOpenGL(window: *glfw.GLFWwindow, install_callbacks: bool) bool;

// Main code
pub fn main() void {
    _ = glfw.glfwSetErrorCallback(&glfw_error_callback);
    if (glfw.glfwInit() == 0) {
        @panic("glfwInit");
    }
    defer glfw.glfwTerminate();

    // Decide GL+GLSL versions
    // #if defined(IMGUI_IMPL_OPENGL_ES2)
    //     // GL ES 2.0 + GLSL 100 (WebGL 1.0)
    //     const char* glsl_version = "#version 100";
    //     glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2);
    //     glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);
    //     glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_ES_API);
    // #elif defined(IMGUI_IMPL_OPENGL_ES3)
    //     // GL ES 3.0 + GLSL 300 es (WebGL 2.0)
    //     const char* glsl_version = "#version 300 es";
    //     glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    //     glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);
    //     glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_ES_API);
    // #elif defined(__APPLE__)
    //     // GL 3.2 + GLSL 150
    //     const char* glsl_version = "#version 150";
    //     glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    //     glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 2);
    //     glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);  // 3.2+ only
    //     glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);            // Required on Mac
    // #else
    // GL 3.0 + GLSL 130
    const glsl_version = "#version 130";
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 2);
    glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE); // 3.2+ only
    glfw.glfwWindowHint(glfw.GLFW_OPENGL_FORWARD_COMPAT, gl.GL_TRUE); // 3.0+ only
    // #endif

    // Create window with graphics context
    const main_scale = c_ImplGlfw_GetContentScaleForMonitor(glfw.glfwGetPrimaryMonitor()); // Valid on GLFW 3.3+ only
    const window = glfw.glfwCreateWindow(
        @intFromFloat(@floor(1280 * main_scale)),
        @intFromFloat(@floor(800 * main_scale)),
        "Dear ImGui GLFW+OpenGL3 example",
        null,
        null,
    ) orelse {
        @panic("glfwCreateWindow");
    };
    defer glfw.glfwDestroyWindow(window);

    glfw.glfwMakeContextCurrent(window);
    _ = gl.gladLoadGL(glfw.glfwGetProcAddress);
    glfw.glfwSwapInterval(1); // Enable vsync

    // Setup Dear ImGui context
    c_ig_CHECKVERSION();
    c_ig_CreateContext();
    const io = c_ig_GetIO();
    _ = io;
    //     io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;     // Enable Keyboard Controls
    //     io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;      // Enable Gamepad Controls

    // Setup Dear ImGui style
    //     ImGui::StyleColorsDark();
    //     //ImGui::StyleColorsLight();

    // Setup scaling
    //     ImGuiStyle& style = ImGui::GetStyle();
    //     style.ScaleAllSizes(main_scale);        // Bake a fixed style scale. (until we have a solution for dynamic style scaling, changing this requires resetting Style + calling this again)
    //     style.FontScaleDpi = main_scale;        // Set initial font scale. (using io.ConfigDpiScaleFonts=true makes this unnecessary. We leave both here for documentation purpose)

    // Setup Platform/Renderer backends
    _ = c_ImplGlfw_InitForOpenGL(window, true);
    _ = c_ImplOpenGL3_Init(glsl_version);

    // Load Fonts
    //     // - If no fonts are loaded, dear imgui will use the default font. You can also load multiple fonts and use ImGui::PushFont()/PopFont() to select them.
    //     // - AddFontFromFileTTF() will return the ImFont* so you can store it if you need to select the font among multiple.
    //     // - If the file cannot be loaded, the function will return a nullptr. Please handle those errors in your application (e.g. use an assertion, or display an error and quit).
    //     // - Use '#define IMGUI_ENABLE_FREETYPE' in your imconfig file to use Freetype for higher quality font rendering.
    //     // - Read 'docs/FONTS.md' for more instructions and details. If you like the default font but want it to scale better, consider using the 'ProggyVector' from the same author!
    //     // - Remember that in C/C++ if you want to include a backslash \ in a string literal you need to write a double backslash \\ !
    //     // - Our Emscripten build process allows embedding fonts to be accessible at runtime from the "fonts/" folder. See Makefile.emscripten for details.
    //     //style.FontSizeBase = 20.0f;
    //     //io.Fonts->AddFontDefault();
    //     //io.Fonts->AddFontFromFileTTF("c:\\Windows\\Fonts\\segoeui.ttf");
    //     //io.Fonts->AddFontFromFileTTF("../../misc/fonts/DroidSans.ttf");
    //     //io.Fonts->AddFontFromFileTTF("../../misc/fonts/Roboto-Medium.ttf");
    //     //io.Fonts->AddFontFromFileTTF("../../misc/fonts/Cousine-Regular.ttf");
    //     //ImFont* font = io.Fonts->AddFontFromFileTTF("c:\\Windows\\Fonts\\ArialUni.ttf");
    //     //IM_ASSERT(font != nullptr);

    // Our state
    var show_demo_window = true;
    //     bool show_another_window = false;
    const clear_color: struct { x: f32, y: f32, z: f32, w: f32 } = .{ .x = 0.45, .y = 0.55, .z = 0.60, .w = 1.00 };

    // Main loop
    while (glfw.glfwWindowShouldClose(window) == 0) {
        //         // Poll and handle events (inputs, window resize, etc.)
        //         // You can read the io.WantCaptureMouse, io.WantCaptureKeyboard flags to tell if dear imgui wants to use your inputs.
        //         // - When io.WantCaptureMouse is true, do not dispatch mouse input data to your main application, or clear/overwrite your copy of the mouse data.
        //         // - When io.WantCaptureKeyboard is true, do not dispatch keyboard input data to your main application, or clear/overwrite your copy of the keyboard data.
        //         // Generally you may always pass all inputs to dear imgui, and hide them from your application based on those two flags.
        glfw.glfwPollEvents();
        if (glfw.glfwGetWindowAttrib(window, glfw.GLFW_ICONIFIED) != 0) {
            //             ImGui_ImplGlfw_Sleep(10);
            continue;
        }

        // Start the Dear ImGui frame
        c_ImplOpenGL3_NewFrame();
        c_ImplGlfw_NewFrame();
        c_ig_NewFrame();

        // 1. Show the big demo window (Most of the sample code is in ImGui::ShowDemoWindow()! You can browse its code to learn more about Dear ImGui!).
        if (show_demo_window)
            c_ig_ShowDemoWindow(&show_demo_window);

        //         // 2. Show a simple window that we create ourselves. We use a Begin/End pair to create a named window.
        //         {
        //             static float f = 0.0f;
        //             static int counter = 0;
        //
        //             ImGui::Begin("Hello, world!");                          // Create a window called "Hello, world!" and append into it.
        //
        //             ImGui::Text("This is some useful text.");               // Display some text (you can use a format strings too)
        //             ImGui::Checkbox("Demo Window", &show_demo_window);      // Edit bools storing our window open/close state
        //             ImGui::Checkbox("Another Window", &show_another_window);
        //
        //             ImGui::SliderFloat("float", &f, 0.0f, 1.0f);            // Edit 1 float using a slider from 0.0f to 1.0f
        //             ImGui::ColorEdit3("clear color", (float*)&clear_color); // Edit 3 floats representing a color
        //
        //             if (ImGui::Button("Button"))                            // Buttons return true when clicked (most widgets return true when edited/activated)
        //                 counter++;
        //             ImGui::SameLine();
        //             ImGui::Text("counter = %d", counter);
        //
        //             ImGui::Text("Application average %.3f ms/frame (%.1f FPS)", 1000.0f / io.Framerate, io.Framerate);
        //             ImGui::End();
        //         }
        //
        //         // 3. Show another simple window.
        //         if (show_another_window)
        //         {
        //             ImGui::Begin("Another Window", &show_another_window);   // Pass a pointer to our bool variable (the window will have a closing button that will clear the bool when clicked)
        //             ImGui::Text("Hello from another window!");
        //             if (ImGui::Button("Close Me"))
        //                 show_another_window = false;
        //             ImGui::End();
        //         }

        // Rendering
        c_ig_Render();
        var display_w: c_int = undefined;
        var display_h: c_int = undefined;
        glfw.glfwGetFramebufferSize(window, &display_w, &display_h);
        gl.glViewport(0, 0, display_w, display_h);
        gl.glClearColor(
            clear_color.x * clear_color.w,
            clear_color.y * clear_color.w,
            clear_color.z * clear_color.w,
            clear_color.w,
        );
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        c_ImplOpenGL3_RenderDrawData(c_ig_GetDrawData());

        glfw.glfwSwapBuffers(window);
    }

    // Cleanup
    //     ImGui_ImplOpenGL3_Shutdown();
    //     ImGui_ImplGlfw_Shutdown();
    //     ImGui::DestroyContext();
}
