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
const imgui = @import("imgui");
const imgui_sokol = @import("imgui_sokol.zig");
const sokol = @import("sokol");

fn T(str: [:0]const u8) [*]u8 {
    return @ptrCast(@constCast(str.ptr));
}

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
    std.log.err("GLFW Error {}: {s}", .{ err, description });
}

const Options = struct {
    no_depth_buffer: bool = false,
    sample_count: c_int = 1,
};

fn glfw_environment(opts: Options) sokol.gfx.Environment {
    return .{
        .defaults = .{
            .color_format = .RGBA8,
            .depth_format = if (opts.no_depth_buffer)
                .NONE
            else
                .DEPTH_STENCIL,
            .sample_count = opts.sample_count,
        },
    };
}

fn glfw_swapchain(_window: *glfw.GLFWwindow, opts: Options) sokol.gfx.Swapchain {
    var width: c_int = undefined;
    var height: c_int = undefined;
    glfw.glfwGetFramebufferSize(_window, &width, &height);
    return .{
        .width = width,
        .height = height,
        .sample_count = opts.sample_count,
        .color_format = .RGBA8,
        .depth_format = if (opts.no_depth_buffer) .NONE else .DEPTH_STENCIL,
        .gl = .{
            // we just assume here that the GL framebuffer is always 0
            .framebuffer = 0,
        },
    };
}
// Main code
pub fn main() !void {
    _ = glfw.glfwSetErrorCallback(glfw_error_callback);
    if (glfw.glfwInit() == 0) {
        @panic("glfwInit");
    }
    defer glfw.glfwTerminate();

    const opts = Options{};

    // GL for sokol
    // const glsl_version: [*:0]const u8 = "#version 130";
    glfw.glfwWindowHint(glfw.GLFW_COCOA_RETINA_FRAMEBUFFER, 0);
    if (opts.no_depth_buffer) {
        glfw.glfwWindowHint(glfw.GLFW_DEPTH_BITS, 0);
        glfw.glfwWindowHint(glfw.GLFW_STENCIL_BITS, 0);
    }
    glfw.glfwWindowHint(glfw.GLFW_SAMPLES, if (opts.sample_count == 1) 0 else opts.sample_count);
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 1);
    glfw.glfwWindowHint(glfw.GLFW_OPENGL_FORWARD_COMPAT, glfw.GLFW_TRUE);
    glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE);

    // Create window with graphics context
    // Valid on GLFW 3.3+ only
    const main_scale = imgui.ImGui_ImplGlfw_GetContentScaleForMonitor(glfw.glfwGetPrimaryMonitor());
    const window = glfw.glfwCreateWindow(
        @intFromFloat(1280 * main_scale),
        @intFromFloat(800 * main_scale),
        "Dear ImGui GLFW+Sokol example",
        null,
        null,
    ) orelse {
        return error.glfwCreateWindow;
    };
    defer glfw.glfwDestroyWindow(window);
    glfw.glfwMakeContextCurrent(window);
    _ = gl.gladLoadGL(glfw.glfwGetProcAddress);
    glfw.glfwSwapInterval(1); // Enable vsync

    // Setup Dear ImGui context
    // IMGUI_CHECKVERSION();

    _ = imgui.CreateContext(.{});
    defer imgui.DestroyContext(.{});
    const io = imgui.GetIO().?;
    io.ConfigFlags |= imgui.ImGuiConfigFlags_NavEnableKeyboard; // Enable Keyboard Controls
    io.ConfigFlags |= imgui.ImGuiConfigFlags_NavEnableGamepad; // Enable Gamepad Controls

    // Setup Dear ImGui style
    imgui.StyleColorsDark(.{});
    //imgui.StyleColorsLight();

    // Setup scaling
    //     ImGuiStyle& style = imgui.GetStyle();
    //     style.ScaleAllSizes(main_scale);        // Bake a fixed style scale. (until we have a solution for dynamic style scaling, changing this requires resetting Style + calling this again)
    //     style.FontScaleDpi = main_scale;        // Set initial font scale. (using io.ConfigDpiScaleFonts=true makes this unnecessary. We leave both here for documentation purpose)

    // Load Fonts
    // - If no fonts are loaded, dear imgui will use the default font. You can also load multiple fonts and use imgui.PushFont()/PopFont() to select them.
    // - AddFontFromFileTTF() will return the ImFont* so you can store it if you need to select the font among multiple.
    // - If the file cannot be loaded, the function will return a nullptr. Please handle those errors in your application (e.g. use an assertion, or display an error and quit).
    // - Use '#define IMGUI_ENABLE_FREETYPE' in your imconfig file to use Freetype for higher quality font rendering.
    // - Read 'docs/FONTS.md' for more instructions and details. If you like the default font but want it to scale better, consider using the 'ProggyVector' from the same author!
    // - Remember that in C/C++ if you want to include a backslash \ in a string literal you need to write a double backslash \\ !
    // - Our Emscripten build process allows embedding fonts to be accessible at runtime from the "fonts/" folder. See Makefile.emscripten for details.
    //     //style.FontSizeBase = 20.0f;
    //     //io.Fonts->AddFontDefault();
    //     //io.Fonts->AddFontFromFileTTF("c:\\Windows\\Fonts\\segoeui.ttf");
    //     //io.Fonts->AddFontFromFileTTF("../../misc/fonts/DroidSans.ttf");
    //     //io.Fonts->AddFontFromFileTTF("../../misc/fonts/Roboto-Medium.ttf");
    //     //io.Fonts->AddFontFromFileTTF("../../misc/fonts/Cousine-Regular.ttf");
    //     //ImFont* font = io.Fonts->AddFontFromFileTTF("c:\\Windows\\Fonts\\ArialUni.ttf");
    //     //IM_ASSERT(font != nullptr);

    // setup sokol_gfx
    const glfw_env: *const sokol.gfx.Environment = @ptrCast(&glfw_environment(opts));
    sokol.gfx.setup(.{
        .environment = glfw_env.*,
        .logger = .{
            .func = sokol.log.func,
        },
    });

    // Setup Platform/Renderer backends
    _ = imgui.ImGui_ImplGlfw_InitForOpenGL(window, true);
    defer imgui.ImGui_ImplGlfw_Shutdown();
    _ = imgui_sokol.ImGui_ImplSokol_Init(&.{});
    defer imgui_sokol.ImGui_ImplSokol_Shutdown();

    // a vertex buffer
    const vertices = [_]f32{
        // positions(.FLOAT3), colors(.FLOAT4)
        0.0,  0.5,  0.5, 1.0, 0.0, 0.0, 1.0,
        0.5,  -0.5, 0.5, 0.0, 1.0, 0.0, 1.0,
        -0.5, -0.5, 0.5, 0.0, 0.0, 1.0, 1.0,
    };
    const vbuf = sokol.gfx.makeBuffer(.{
        .data = sokol.gfx.asRange(&vertices),
    });

    // a shader
    const shd = sokol.gfx.makeShader(
        .{
            .vertex_func = .{ .source = 
            \\#version 410
            \\layout(location=0) in vec4 position;
            \\layout(location=1) in vec4 color0;
            \\out vec4 color;
            \\void main() {
            \\  gl_Position = position;
            \\  color = color0;
            \\}
            \\
        },
            .fragment_func = .{ .source = 
            \\#version 410
            \\in vec4 color;
            \\out vec4 frag_color;
            \\void main() {
            \\  frag_color = color;
            \\}
            \\
        },
        },
    );

    // a pipeline state object (default render states are fine for triangle)
    var pipDesc = sokol.gfx.PipelineDesc{
        .shader = shd,
    };
    pipDesc.layout.attrs[0].format = .FLOAT3;
    pipDesc.layout.attrs[1].format = .FLOAT4;
    const pip = sokol.gfx.makePipeline(pipDesc);

    // resource bindings
    const bind = sokol.gfx.Bindings{
        .vertex_buffers = .{ vbuf, .{}, .{}, .{}, .{}, .{}, .{}, .{} },
    };

    // Our state
    var show_demo_window = true;
    var show_another_window = false;
    var clear_color = imgui.ImVec4{ .x = 0.45, .y = 0.55, .z = 0.60, .w = 1.00 };
    var f: f32 = 0.0;
    var counter: u32 = 0;

    // Main loop
    while (glfw.glfwWindowShouldClose(window) == 0) {
        // Poll and handle events (inputs, window resize, etc.)
        // You can read the io.WantCaptureMouse, io.WantCaptureKeyboard flags to tell if dear imgui wants to use your inputs.
        // - When io.WantCaptureMouse is true, do not dispatch mouse input data to your main application, or clear/overwrite your copy of the mouse data.
        // - When io.WantCaptureKeyboard is true, do not dispatch keyboard input data to your main application, or clear/overwrite your copy of the keyboard data.
        // Generally you may always pass all inputs to dear imgui, and hide them from your application based on those two flags.
        glfw.glfwPollEvents();
        if (glfw.glfwGetWindowAttrib(window, glfw.GLFW_ICONIFIED) != 0) {
            imgui.ImGui_ImplGlfw_Sleep(10);
            continue;
        }

        // Start the Dear ImGui frame
        // imgui_sokol.ImGui_ImplSokol_NewFrame();
        imgui.ImGui_ImplGlfw_NewFrame();
        imgui.NewFrame();

        // 1. Show the big demo window (Most of the sample code is in imgui.ShowDemoWindow()! You can browse its code to learn more about Dear ImGui!).
        if (show_demo_window)
            imgui.ShowDemoWindow(.{ .p_open = &show_demo_window });

        // 2. Show a simple window that we create ourselves. We use a Begin/End pair to create a named window.
        {
            _ = imgui.Begin(T("Hello, world!"), .{}); // Create a window called "Hello, world!" and append into it.

            imgui.Text(T("This is some useful text."), .{}); // Display some text (you can use a format strings too)
            _ = imgui.Checkbox(T("Demo Window"), &show_demo_window); // Edit bools storing our window open/close state
            _ = imgui.Checkbox(T("Another Window"), &show_another_window);

            _ = imgui.SliderFloat(T("float"), &f, 0.0, 1.0, .{}); // Edit 1 float using a slider from 0.0f to 1.0f
            _ = imgui.ColorEdit3(T("clear color"), &clear_color.x, .{}); // Edit 3 floats representing a color

            if (imgui.Button(T("Button"), .{})) // Buttons return true when clicked (most widgets return true when edited/activated)
                counter += 1;
            imgui.SameLine(.{});
            imgui.Text(T("counter = %d"), .{counter});
            imgui.Text(T("Application average %.3f ms/frame (%.1f FPS)"), .{ 1000.0 / io.Framerate, io.Framerate });
            imgui.End();
        }

        // 3. Show another simple window.
        if (show_another_window) {
            // Pass a pointer to our bool variable
            // (the window will have a closing button that will clear the bool when clicked)
            _ = imgui.Begin(T("Another Window"), .{ .p_open = &show_another_window });
            imgui.Text(T("Hello from another window!"), .{});
            if (imgui.Button(T("Close Me"), .{}))
                show_another_window = false;
            imgui.End();
        }

        // Rendering
        imgui.Render();

        var display_w: c_int = undefined;
        var display_h: c_int = undefined;
        glfw.glfwGetFramebufferSize(window, &display_w, &display_h);
        gl.glViewport(0, 0, display_w, display_h);
        gl.glClearColor(clear_color.x * clear_color.w, clear_color.y * clear_color.w, clear_color.z * clear_color.w, clear_color.w);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);

        const sc: *const sokol.gfx.Swapchain = @ptrCast(&glfw_swapchain(window, opts));
        sokol.gfx.beginPass(.{ .swapchain = sc.* });
        sokol.gfx.applyPipeline(pip);
        sokol.gfx.applyBindings(bind);
        sokol.gfx.draw(0, 3, 1);

        imgui_sokol.ImGui_ImplSokol_RenderDrawData(imgui.GetDrawData());
        sokol.gfx.endPass();
        sokol.gfx.commit();

        glfw.glfwSwapBuffers(window);
    }
}
