#include "imgui_without_mangling.h"
#include "imgui.h"
#include <backends/imgui_impl_glfw.h>
#include <backends/imgui_impl_opengl3.h>

void c_ig_CHECKVERSION() { IMGUI_CHECKVERSION(); }

void c_ig_CreateContext() { ImGui::CreateContext(); }

ImGuiIO *c_ig_GetIO() { return &ImGui::GetIO(); }

void c_ig_NewFrame() { ImGui::NewFrame(); }

void c_ig_ShowDemoWindow(bool *show_demo_window) {
  ImGui::ShowDemoWindow(show_demo_window);
}

void c_ig_Render() { ImGui::Render(); }
ImDrawData *c_ig_GetDrawData() { return ImGui::GetDrawData(); }

//
// backend OpenGL3
//
bool c_ImplOpenGL3_Init(const char *glsl_version) {
  return ImGui_ImplOpenGL3_Init(glsl_version);
}

void c_ImplOpenGL3_NewFrame() { ImGui_ImplOpenGL3_NewFrame(); }

void c_ImplOpenGL3_RenderDrawData(ImDrawData *data) {
  ImGui_ImplOpenGL3_RenderDrawData(data);
}

//
// backend glfw
//
bool c_ImplGlfw_InitForOpenGL(GLFWwindow *window, bool install_callbacks) {
  return ImGui_ImplGlfw_InitForOpenGL(window, install_callbacks);
}

void c_ImplGlfw_NewFrame() { ImGui_ImplGlfw_NewFrame(); }

float c_ImplGlfw_GetContentScaleForMonitor(GLFWmonitor *monitor) {
  return ImGui_ImplGlfw_GetContentScaleForMonitor(monitor);
}
