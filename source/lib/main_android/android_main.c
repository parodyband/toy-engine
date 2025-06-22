// Android entry point for the toy engine
#include <android/log.h>
#include <android/native_activity.h>
#include <android_native_app_glue.h>
#include <android/asset_manager.h>
#include <android/input.h>
#include <pthread.h>
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <string.h>
#include <unistd.h>
#include <jni.h>

#define LOG_TAG "ToyEngine"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Forward declarations for Odin functions
extern void odin_android_init(void);
extern void odin_android_frame(void);
extern void odin_android_cleanup(void);
extern void odin_android_set_asset_manager(void* mgr);
extern void odin_android_touch(float x, float y, int action);

// Forward declarations for sokol stub functions
extern void sapp_android_set_egl_display(void* display);
extern void sapp_android_set_egl_context(void* context);
extern void sapp_android_set_egl_surface(void* surface);
extern void sapp_android_set_window_size(int width, int height);
extern void sapp_android_set_native_window(void* window);

// Global state
static EGLDisplay egl_display = EGL_NO_DISPLAY;
static EGLSurface egl_surface = EGL_NO_SURFACE;
static EGLContext egl_context = EGL_NO_CONTEXT;
static int initialized = 0;
static int animating = 0;
static AAssetManager* asset_manager = NULL;
static ANativeWindow* native_window;
static bool has_focus = false;

// Initialize EGL
static int init_egl(ANativeWindow* window) {
    LOGI("Initializing EGL");
    
    // Store the native window for sokol
    sapp_android_set_native_window(window);
    LOGI("Set native window for sokol");
    
    egl_display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (egl_display == EGL_NO_DISPLAY) {
        LOGE("eglGetDisplay failed");
        return 0;
    }
    
    EGLint major, minor;
    if (!eglInitialize(egl_display, &major, &minor)) {
        LOGE("eglInitialize failed");
        return 0;
    }
    LOGI("EGL version: %d.%d", major, minor);
    
    // Choose config
    EGLint config_attribs[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_BLUE_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_RED_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_DEPTH_SIZE, 24,
        EGL_STENCIL_SIZE, 8,
        EGL_NONE
    };
    
    EGLConfig config;
    EGLint num_configs;
    if (!eglChooseConfig(egl_display, config_attribs, &config, 1, &num_configs) || num_configs == 0) {
        LOGE("eglChooseConfig failed");
        return 0;
    }
    
    // Create context
    EGLint context_attribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE
    };
    
    egl_context = eglCreateContext(egl_display, config, EGL_NO_CONTEXT, context_attribs);
    if (egl_context == EGL_NO_CONTEXT) {
        LOGE("eglCreateContext failed");
        return 0;
    }
    
    // Create surface
    egl_surface = eglCreateWindowSurface(egl_display, config, window, NULL);
    if (egl_surface == EGL_NO_SURFACE) {
        LOGE("eglCreateWindowSurface failed");
        return 0;
    }
    
    // Make current
    if (!eglMakeCurrent(egl_display, egl_surface, egl_surface, egl_context)) {
        LOGE("eglMakeCurrent failed");
        return 0;
    }
    
    // Log OpenGL info
    LOGI("OpenGL ES version: %s", glGetString(GL_VERSION));
    LOGI("OpenGL ES vendor: %s", glGetString(GL_VENDOR));
    LOGI("OpenGL ES renderer: %s", glGetString(GL_RENDERER));
    
    // Get window size
    EGLint width, height;
    eglQuerySurface(egl_display, egl_surface, EGL_WIDTH, &width);
    eglQuerySurface(egl_display, egl_surface, EGL_HEIGHT, &height);
    LOGI("Window size: %dx%d", width, height);
    
    // Update sokol stubs with EGL state
    sapp_android_set_egl_display(egl_display);
    sapp_android_set_egl_context(egl_context);
    sapp_android_set_egl_surface(egl_surface);
    sapp_android_set_window_size(width, height);
    
    return 1;
}

// Cleanup EGL
static void cleanup_egl() {
    if (egl_display != EGL_NO_DISPLAY) {
        eglMakeCurrent(egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        
        if (egl_context != EGL_NO_CONTEXT) {
            eglDestroyContext(egl_display, egl_context);
            egl_context = EGL_NO_CONTEXT;
        }
        
        if (egl_surface != EGL_NO_SURFACE) {
            eglDestroySurface(egl_display, egl_surface);
            egl_surface = EGL_NO_SURFACE;
        }
        
        eglTerminate(egl_display);
        egl_display = EGL_NO_DISPLAY;
    }
}

// Draw frame
static void draw_frame() {
    if (egl_display == EGL_NO_DISPLAY) {
        return;
    }
    
    odin_android_frame();
    eglSwapBuffers(egl_display, egl_surface);
}

// Handle input
static int32_t handle_input(struct android_app* app, AInputEvent* event) {
    static int move_count = 0;  // Move static declaration here
    
    if (AInputEvent_getType(event) == AINPUT_EVENT_TYPE_MOTION) {
        int action = AMotionEvent_getAction(event);
        int action_type = action & AMOTION_EVENT_ACTION_MASK;
        
        float x = AMotionEvent_getX(event, 0);
        float y = AMotionEvent_getY(event, 0);
        
        // Convert Android motion events to simple touch actions
        // 0 = down, 1 = up, 2 = move
        switch (action_type) {
            case AMOTION_EVENT_ACTION_DOWN:
                LOGI("Touch down at: %.1f, %.1f", x, y);
                odin_android_touch(x, y, 0);
                return 1;
                
            case AMOTION_EVENT_ACTION_UP:
                LOGI("Touch up at: %.1f, %.1f", x, y);
                odin_android_touch(x, y, 1);
                return 1;
                
            case AMOTION_EVENT_ACTION_MOVE:
                // Only log every 10th move event to reduce spam
                if (++move_count % 10 == 0) {
                    LOGI("Touch move at: %.1f, %.1f", x, y);
                }
                odin_android_touch(x, y, 2);
                return 1;
        }
    }
    return 0;
}

// Handle app commands
static void handle_cmd(struct android_app* app, int32_t cmd) {
    switch (cmd) {
        case APP_CMD_INIT_WINDOW:
            LOGI("APP_CMD_INIT_WINDOW");
            if (app->window != NULL) {
                if (init_egl(app->window)) {
                    if (!initialized) {
                        // Get and store the asset manager
                        if (app->activity != NULL) {
                            asset_manager = app->activity->assetManager;
                            LOGI("Got asset manager: %p", asset_manager);
                            
                            // Pass asset manager to Odin code
                            odin_android_set_asset_manager(asset_manager);
                        }
                        
                        LOGI("Calling odin_android_init");
                        odin_android_init();
                        initialized = 1;
                    }
                    animating = 1;
                }
            }
            break;
            
        case APP_CMD_TERM_WINDOW:
            LOGI("APP_CMD_TERM_WINDOW");
            animating = 0;
            cleanup_egl();
            break;
            
        case APP_CMD_GAINED_FOCUS:
            LOGI("APP_CMD_GAINED_FOCUS");
            animating = 1;
            break;
            
        case APP_CMD_LOST_FOCUS:
            LOGI("APP_CMD_LOST_FOCUS");
            animating = 0;
            break;
            
        case APP_CMD_DESTROY:
            LOGI("APP_CMD_DESTROY");
            if (initialized) {
                odin_android_cleanup();
                initialized = 0;
            }
            break;
    }
}

// Main entry point
void android_main(struct android_app* app) {
    LOGI("android_main called");
    
    app->onAppCmd = handle_cmd;
    app->onInputEvent = handle_input;
    
    // Main loop
    while (1) {
        int events;
        struct android_poll_source* source;
        
        // Process events
        while (ALooper_pollOnce(animating ? 0 : -1, NULL, &events, (void**)&source) >= 0) {
            if (source != NULL) {
                source->process(app, source);
            }
            
            if (app->destroyRequested != 0) {
                LOGI("Destroy requested, exiting");
                return;
            }
        }
        
        // Draw frame if animating
        if (animating && initialized) {
            draw_frame();
        }
    }
}

// C wrapper functions for Android asset operations (called from Odin)
void* android_asset_open(const char* filename, int mode) {
    LOGI("android_asset_open called for: %s", filename);
    if (asset_manager == NULL) {
        LOGE("Asset manager is NULL in android_asset_open");
        return NULL;
    }
    void* asset = AAssetManager_open(asset_manager, filename, mode);
    if (asset == NULL) {
        LOGE("AAssetManager_open returned NULL for: %s", filename);
    } else {
        LOGI("Successfully opened asset: %s", filename);
    }
    return asset;
}

int android_asset_read(void* asset, void* buf, size_t count) {
    return AAsset_read((AAsset*)asset, buf, count);
}

long android_asset_get_length(void* asset) {
    return AAsset_getLength((AAsset*)asset);
}

void android_asset_close(void* asset) {
    AAsset_close((AAsset*)asset);
} 