const std = @import("std");
const glfw = @import("glfw");
const gl = @import("glad");
const linmath = @import("linmath.zig");

const Vertex = struct {
    pos: linmath.vec2,
    col: linmath.vec3,
};

const vertices = [_]Vertex{
    .{ .pos = .{ -0.6, -0.4 }, .col = .{ 1.0, 0.0, 0.0 } },
    .{ .pos = .{ 0.6, -0.4 }, .col = .{ 0.0, 1.0, 0.0 } },
    .{ .pos = .{ 0.0, 0.6 }, .col = .{ 0.0, 0.0, 1.0 } },
};

const vertex_shader_text =
    \\#version 330
    \\uniform mat4 MVP;
    \\in vec3 vCol;
    \\in vec2 vPos;
    \\out vec3 color;
    \\void main()
    \\{
    \\    gl_Position = MVP * vec4(vPos, 0.0, 1.0);
    \\    color = vCol;
    \\}
;

const fragment_shader_text =
    \\#version 330
    \\in vec3 color;
    \\out vec4 fragment;
    \\void main()
    \\{
    \\    fragment = vec4(color, 1.0);
    \\}
;

export fn error_callback(err: c_int, description: [*c]const u8) void {
    _ = err;
    std.debug.print("Error: {s}\n", .{description});
}

export fn key_callback(
    window: ?*glfw.GLFWwindow,
    key: c_int,
    scancode: c_int,
    action: c_int,
    mods: c_int,
) void {
    _ = scancode;
    _ = mods;
    if (key == glfw.GLFW_KEY_ESCAPE and action == glfw.GLFW_PRESS) {
        glfw.glfwSetWindowShouldClose(window, glfw.GLFW_TRUE);
    }
}

pub fn main() void {
    _ = glfw.glfwSetErrorCallback(error_callback);

    if (glfw.glfwInit() == 0) {
        @panic("glfwInit");
    }
    defer glfw.glfwTerminate();

    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 3);
    glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE);

    const window = glfw.glfwCreateWindow(640, 480, "OpenGL Triangle", null, null) orelse {
        @panic("glfwCreateWindow");
    };
    defer glfw.glfwDestroyWindow(window);

    _ = glfw.glfwSetKeyCallback(window, key_callback);

    glfw.glfwMakeContextCurrent(window);
    _ = gl.gladLoadGL(glfw.glfwGetProcAddress);
    glfw.glfwSwapInterval(1);

    // NOTE: OpenGL error checks have been omitted for brevity

    var vertex_buffer: gl.GLuint = undefined;
    gl.glGenBuffers(1, &vertex_buffer);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vertex_buffer);
    gl.glBufferData(gl.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices[0], gl.GL_STATIC_DRAW);

    const vertex_shader: gl.GLuint = gl.glCreateShader(gl.GL_VERTEX_SHADER);
    gl.glShaderSource(vertex_shader, 1, &&vertex_shader_text[0], null);
    gl.glCompileShader(vertex_shader);

    const fragment_shader: gl.GLuint = gl.glCreateShader(gl.GL_FRAGMENT_SHADER);
    gl.glShaderSource(fragment_shader, 1, &&fragment_shader_text[0], null);
    gl.glCompileShader(fragment_shader);

    const program: gl.GLuint = gl.glCreateProgram();
    gl.glAttachShader(program, vertex_shader);
    gl.glAttachShader(program, fragment_shader);
    gl.glLinkProgram(program);

    const mvp_location = gl.glGetUniformLocation(program, "MVP");
    const vpos_location = gl.glGetAttribLocation(program, "vPos");
    const vcol_location = gl.glGetAttribLocation(program, "vCol");

    var vertex_array: gl.GLuint = undefined;
    gl.glGenVertexArrays(1, &vertex_array);
    gl.glBindVertexArray(vertex_array);
    gl.glEnableVertexAttribArray(@intCast(vpos_location));
    gl.glVertexAttribPointer(
        @intCast(vpos_location),
        2,
        gl.GL_FLOAT,
        gl.GL_FALSE,
        @sizeOf(Vertex),
        @ptrFromInt(@offsetOf(Vertex, "pos")),
    );
    gl.glEnableVertexAttribArray(@intCast(vcol_location));
    gl.glVertexAttribPointer(
        @intCast(vcol_location),
        3,
        gl.GL_FLOAT,
        gl.GL_FALSE,
        @sizeOf(Vertex),
        @ptrFromInt(@offsetOf(Vertex, "col")),
    );

    while (glfw.glfwWindowShouldClose(window) == 0) {
        var width: c_int = undefined;
        var height: c_int = undefined;
        glfw.glfwGetFramebufferSize(window, &width, &height);
        const ratio = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));

        gl.glViewport(0, 0, width, height);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);

        var m: linmath.mat4x4 = undefined;
        var mvp: linmath.mat4x4 = undefined;
        linmath.mat4x4_identity(&m);
        linmath.mat4x4_rotate_Z(&m, m, @floatCast(glfw.glfwGetTime()));
        var p: linmath.mat4x4 = undefined;
        linmath.mat4x4_ortho(&p, -ratio, ratio, -1.0, 1.0, 1.0, -1.0);
        linmath.mat4x4_mul(&mvp, p, m);

        gl.glUseProgram(program);
        gl.glUniformMatrix4fv(mvp_location, 1, gl.GL_FALSE, &mvp[0]);
        gl.glBindVertexArray(vertex_array);
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 3);

        glfw.glfwSwapBuffers(window);
        glfw.glfwPollEvents();
    }
}
