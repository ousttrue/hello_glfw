# project
cmake_minimum_required(VERSION 3.20.0)
project(hello_glfw VERSION 0.1.0)

# for compile_commands.json
set(CMAKE_EXPORT_COMPILE_COMMANDS 1)

# for build/.gitignore
if(NOT PROJECT_SOURCE_DIR STREQUAL PROJECT_BINARY_DIR)
  file(
    GENERATE
    OUTPUT ${PROJECT_BINARY_DIR}/.gitignore
    CONTENT "*")
endif()

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

# target
set(TARGET_NAME ${PROJECT_NAME})
add_executable(${TARGET_NAME} 
  main.c
)
target_link_libraries(${TARGET_NAME} PRIVATE glfw)
target_include_directories(${TARGET_NAME} PRIVATE 
  # inmath.h / gl/glad.h
  ${glfw_SOURCE_DIR}/deps
)
