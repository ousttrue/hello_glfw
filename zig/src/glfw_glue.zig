// https://github.com/floooh/sokol-samples/blob/master/glfw/glfw_glue.c
const std = @import("std");
const sokol = @import("sokol");
const glfw = @import("glfw");
pub const glfwWindowShouldClose = glfw.glfwWindowShouldClose;
pub const glfwSwapBuffers = glfw.glfwSwapBuffers;
pub const glfwPollEvents = glfw.glfwPollEvents;
pub const glfwTerminate = glfw.glfwTerminate;

var _sample_count: i32 = 0;
var _no_depth_buffer = false;
var _major_version: i32 = 0;
var _minor_version: i32 = 0;
var _window: ?*glfw.GLFWwindow = null;

fn _glfw_def(val: i32, def: i32) i32 {
    return if (val == 0) (def) else (val);
}

const glfw_desc_t = struct {
    width: i32,
    height: i32,
    sample_count: i32 = 0,
    no_depth_buffer: bool,
    title: [:0]const u8,
    version_major: i32 = 0,
    version_minor: i32 = 0,
};

pub fn glfw_init(desc: *const glfw_desc_t) void {
    std.debug.assert(desc.width > 0);
    std.debug.assert(desc.height > 0);
    var desc_def = desc.*;
    desc_def.sample_count = _glfw_def(desc_def.sample_count, 1);
    desc_def.version_major = _glfw_def(desc_def.version_major, 4);
    desc_def.version_minor = _glfw_def(desc_def.version_minor, 1);
    _sample_count = desc_def.sample_count;
    _no_depth_buffer = desc_def.no_depth_buffer;
    _major_version = desc_def.version_major;
    _minor_version = desc_def.version_minor;
    _ = glfw.glfwInit();
    glfw.glfwWindowHint(glfw.GLFW_COCOA_RETINA_FRAMEBUFFER, 0);
    if (desc_def.no_depth_buffer) {
        glfw.glfwWindowHint(glfw.GLFW_DEPTH_BITS, 0);
        glfw.glfwWindowHint(glfw.GLFW_STENCIL_BITS, 0);
    }
    glfw.glfwWindowHint(glfw.GLFW_SAMPLES, if (desc_def.sample_count == 1) 0 else desc_def.sample_count);
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, desc_def.version_major);
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, desc_def.version_minor);
    glfw.glfwWindowHint(glfw.GLFW_OPENGL_FORWARD_COMPAT, glfw.GLFW_TRUE);
    glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE);
    _window = glfw.glfwCreateWindow(desc_def.width, desc_def.height, desc_def.title, null, null);
    glfw.glfwMakeContextCurrent(_window);
    glfw.glfwSwapInterval(1);
}

pub fn glfw_window() ?*glfw.GLFWwindow {
    return _window;
}

pub fn glfw_width() c_int {
    var width: c_int = undefined;
    var height: c_int = undefined;
    glfw.glfwGetFramebufferSize(_window, &width, &height);
    return width;
}

pub fn glfw_height() c_int {
    var width: c_int = undefined;
    var height: c_int = undefined;
    glfw.glfwGetFramebufferSize(_window, &width, &height);
    return height;
}

pub fn glfw_environment() sokol.gfx.Environment {
    return .{
        .defaults = .{
            .color_format = .RGBA8,
            .depth_format = if (_no_depth_buffer)
                .NONE
            else
                .DEPTH_STENCIL,
            .sample_count = _sample_count,
        },
    };
}

pub fn glfw_swapchain() sokol.gfx.Swapchain {
    var width: c_int = undefined;
    var height: c_int = undefined;
    glfw.glfwGetFramebufferSize(_window, &width, &height);
    return .{
        .width = width,
        .height = height,
        .sample_count = _sample_count,
        .color_format = .RGBA8,
        .depth_format = if (_no_depth_buffer) .NONE else .DEPTH_STENCIL,
        .gl = .{
            // we just assume here that the GL framebuffer is always 0
            .framebuffer = 0,
        },
    };
}
