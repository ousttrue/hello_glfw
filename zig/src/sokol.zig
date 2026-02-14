//------------------------------------------------------------------------------
//  triangle-glfw.c
//  Vertex buffer, simple shader, pipeline state object.
//------------------------------------------------------------------------------
const glfw = @import("glfw_glue.zig");
const sokol = @import("sokol");
const std = @import("std");

pub fn main() void {

    // create window and GL context via GLFW
    glfw.glfw_init(&.{
        .title = "sokol_glfw_triangle",
        .width = 640,
        .height = 480,
        .no_depth_buffer = true,
    });

    // setup sokol_gfx
    const glfw_env: *const sokol.gfx.Environment = @ptrCast(&glfw.glfw_environment());
    sokol.gfx.setup(.{
        .environment = glfw_env.*,
        .logger = .{
            .func = sokol.log.func,
        },
    });

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

    // draw loop
    while (glfw.glfwWindowShouldClose(glfw.glfw_window()) == 0) {
        const sc: *const sokol.gfx.Swapchain = @ptrCast(&glfw.glfw_swapchain());
        sokol.gfx.beginPass(.{ .swapchain = sc.* });
        sokol.gfx.applyPipeline(pip);
        sokol.gfx.applyBindings(bind);
        sokol.gfx.draw(0, 3, 1);
        sokol.gfx.endPass();
        sokol.gfx.commit();
        glfw.glfwSwapBuffers(glfw.glfw_window());
        glfw.glfwPollEvents();
    }

    // cleanup
    sokol.gfx.shutdown();
    glfw.glfwTerminate();
}
