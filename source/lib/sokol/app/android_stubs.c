// Stub implementations of sokol_app functions for Android
// This is needed because the toy engine uses its own main function
// but still references sokol_app functions

#include <stdint.h>
#include <stdbool.h>
#include <EGL/egl.h>
#include <android/native_window.h>

// Stub types
typedef struct { int dummy; } sapp_desc;
typedef struct { int dummy; } sapp_icon_desc;
typedef struct { int dummy; } sapp_html5_fetch_request;
typedef enum { SAPP_MOUSECURSOR_DEFAULT = 0 } sapp_mouse_cursor;

// Global EGL state (will be initialized by our android_main.c)
static EGLDisplay g_egl_display = EGL_NO_DISPLAY;
static EGLContext g_egl_context = EGL_NO_CONTEXT;
static EGLSurface g_egl_surface = EGL_NO_SURFACE;
static int g_width = 1080;  // Default width
static int g_height = 2400; // Default height
static float g_dpi_scale = 1.0f;
static ANativeWindow* g_native_window = NULL;
static bool g_initialized = false;

// Helper to update window size from EGL
static void update_window_size() {
    if (g_egl_display != EGL_NO_DISPLAY && g_egl_surface != EGL_NO_SURFACE) {
        EGLint w, h;
        if (eglQuerySurface(g_egl_display, g_egl_surface, EGL_WIDTH, &w)) {
            g_width = w;
        }
        if (eglQuerySurface(g_egl_display, g_egl_surface, EGL_HEIGHT, &h)) {
            g_height = h;
        }
    }
}

// Export functions to set EGL state
__attribute__((visibility("default")))
void sapp_android_set_egl_display(void* display) {
    g_egl_display = (EGLDisplay)display;
    update_window_size();
}

__attribute__((visibility("default")))
void sapp_android_set_egl_context(void* context) {
    g_egl_context = (EGLContext)context;
}

__attribute__((visibility("default")))
void sapp_android_set_egl_surface(void* surface) {
    g_egl_surface = (EGLSurface)surface;
    update_window_size();
}

__attribute__((visibility("default")))
void sapp_android_set_window_size(int width, int height) {
    g_width = width;
    g_height = height;
}

// Add this function with proper visibility
__attribute__((visibility("default")))
void sapp_android_set_native_window(void* window) {
    g_native_window = (ANativeWindow*)window;
    g_initialized = true;
}

// Common sokol_app functions that might be referenced
bool sapp_isvalid(void) { return g_initialized; }
int sapp_width(void) { 
    update_window_size();
    return g_width; 
}

float sapp_widthf(void) { 
    update_window_size();
    return (float)g_width; 
}

int sapp_height(void) { 
    update_window_size();
    return g_height; 
}

float sapp_heightf(void) { 
    update_window_size();
    return (float)g_height; 
}

int sapp_color_format(void) { 
    // For GL backends: SG_PIXELFORMAT_RGBA8 = 23
    return 23;  // RGBA8
}
int sapp_depth_format(void) { 
    // SG_PIXELFORMAT_DEPTH = 45
    return 45;  // DEPTH
}
int sapp_sample_count(void) { return 1; }
bool sapp_high_dpi(void) { return false; }
float sapp_dpi_scale(void) { return g_dpi_scale; }
void sapp_show_keyboard(bool show) { }
bool sapp_keyboard_shown(void) { return false; }
bool sapp_is_fullscreen(void) { return true; }
void sapp_toggle_fullscreen(void) { }
void sapp_show_mouse(bool show) { }
bool sapp_mouse_shown(void) { return true; }
void sapp_lock_mouse(bool lock) { }
bool sapp_mouse_locked(void) { return false; }
void sapp_set_mouse_cursor(sapp_mouse_cursor cursor) { }
sapp_mouse_cursor sapp_get_mouse_cursor(void) { return SAPP_MOUSECURSOR_DEFAULT; }
void* sapp_userdata(void) { return 0; }
sapp_desc sapp_query_desc(void) { sapp_desc d = {0}; return d; }
void sapp_request_quit(void) { }
void sapp_cancel_quit(void) { }
void sapp_quit(void) { }
void sapp_consume_event(void) { }
uint64_t sapp_frame_count(void) { return 0; }
double sapp_frame_duration(void) { return 0.016667; }
void sapp_set_clipboard_string(const char* str) { }
const char* sapp_get_clipboard_string(void) { return ""; }
void sapp_set_window_title(const char* str) { }
void sapp_set_icon(const sapp_icon_desc* icon_desc) { }
int sapp_get_num_dropped_files(void) { return 0; }
const char* sapp_get_dropped_file_path(int index) { return ""; }
void sapp_run(const sapp_desc* desc) { }

// EGL functions - return the actual EGL context if available
const void* sapp_egl_get_display(void) { return g_egl_display; }
const void* sapp_egl_get_context(void) { return g_egl_context; }

// HTML5 functions
void sapp_html5_ask_leave_site(bool ask) { }
uint32_t sapp_html5_get_dropped_file_size(int index) { return 0; }
void sapp_html5_fetch_dropped_file(const sapp_html5_fetch_request* request) { }

// Metal functions
const void* sapp_metal_get_device(void) { return 0; }
const void* sapp_metal_get_current_drawable(void) { return 0; }
const void* sapp_metal_get_depth_stencil_texture(void) { return 0; }
const void* sapp_metal_get_msaa_color_texture(void) { return 0; }
const void* sapp_metal_get_drawable(void) { return 0; }  // Older name
const void* sapp_metal_get_renderpass_descriptor(void) { return 0; }  // Older name

// macOS/iOS functions
const void* sapp_macos_get_window(void) { return 0; }
const void* sapp_ios_get_window(void) { return 0; }

// D3D11 functions
const void* sapp_d3d11_get_device(void) { return 0; }
const void* sapp_d3d11_get_device_context(void) { return 0; }
const void* sapp_d3d11_get_swap_chain(void) { return 0; }
const void* sapp_d3d11_get_render_view(void) { return 0; }
const void* sapp_d3d11_get_resolve_view(void) { return 0; }
const void* sapp_d3d11_get_depth_stencil_view(void) { return 0; }
const void* sapp_d3d11_get_render_target_view(void) { return 0; }  // Older name

// Win32 functions
const void* sapp_win32_get_hwnd(void) { return 0; }

// WebGPU functions
const void* sapp_wgpu_get_device(void) { return 0; }
const void* sapp_wgpu_get_render_view(void) { return 0; }
const void* sapp_wgpu_get_resolve_view(void) { return 0; }
const void* sapp_wgpu_get_depth_stencil_view(void) { return 0; }

// OpenGL functions
uint32_t sapp_gl_get_framebuffer(void) { return 0; }
int sapp_gl_get_major_version(void) { return 3; }
int sapp_gl_get_minor_version(void) { return 0; }
bool sapp_gl_is_gles(void) { return true; }

// X11 functions
const void* sapp_x11_get_window(void) { return 0; }
const void* sapp_x11_get_display(void) { return 0; }

// Android functions
const void* sapp_android_get_native_activity(void) { return 0; }
const void* sapp_android_get_native_window(void) { return g_native_window; } 