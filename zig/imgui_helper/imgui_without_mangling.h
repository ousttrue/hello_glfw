#pragma once
#include <GLFW/glfw3.h>

#ifdef __cplusplus
extern "C" {
#endif

void c_ig_CHECKVERSION(void);
void c_ig_CreateContext();
struct ImGuiIO *c_ig_GetIO();
void c_ig_NewFrame();
void c_ig_ShowDemoWindow(bool *show_demo_window);
void c_ig_Render();
struct ImDrawData *c_ig_GetDrawData();

//
// backend
//
bool c_ImplGlfw_InitForOpenGL(GLFWwindow *window, bool install_callbacks);
bool c_ImplOpenGL3_Init(const char *glsl_version);
void c_ImplOpenGL3_NewFrame();
void c_ImplOpenGL3_RenderDrawData(ImDrawData *data);

// GLFW helpers
void c_ImplGlfw_NewFrame();
void c_ImplGlfw_Sleep(int milliseconds);
float c_ImplGlfw_GetContentScaleForWindow(GLFWwindow *window);
float c_ImplGlfw_GetContentScaleForMonitor(GLFWmonitor *monitor);

#ifdef __cplusplus
}
#endif
