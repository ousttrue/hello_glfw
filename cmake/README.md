# cmake

glfw-3.4 is required for GLAD_GL_IMPLEMENTATION ?

```cmake
include(FetchContent)
set(BUILD_SHARED_LIBS OFF)
set(GLFW_BUILD_EXAMPLES OFF)
set(GLFW_BUILD_TESTS OFF)
set(GLFW_BUILD_DOCS OFF)

FetchContent_Declare(
  glfw
  GIT_REPOSITORY https://github.com/glfw/glfw.git
  GIT_TAG 3.4)
FetchContent_MakeAvailable(glfw)
```

## src

https://www.glfw.org/docs/latest/quick_guide.html#quick_example

## wayland

```sh
cmake -S . -B build -DGLFW_BUILD_WAYLAND=on
cmake --build build

ldd ./build/hello_glfw
        linux-vdso.so.1 (0x00007fa0e0c8c000)
        libm.so.6 => /usr/lib64/libm.so.6 (0x00007fa0e0acc000)
        libc.so.6 => /usr/lib64/libc.so.6 (0x00007fa0e08e1000)
        /lib64/ld-linux-x86-64.so.2 (0x00007fa0e0c8e000)
```
