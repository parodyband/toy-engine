/*
Android-specific main file that exports functions for the Android build.
This is needed because Android uses NativeActivity which requires specific entry points.
*/

package main_android

import "core:os"
import "core:mem"
import "base:runtime"
import "core:log"
import "core:c"
import game "../../"
import gltf "../../lib/glTF2"
import sapp "../../lib/sokol/app"

_ :: mem
_ :: runtime

USE_TRACKING_ALLOCATOR :: #config(USE_TRACKING_ALLOCATOR, false)

custom_context: runtime.Context

// Android asset manager types
AAssetManager :: struct {}
AAsset :: struct {}

AASSET_MODE_BUFFER :: 3

// Global asset manager set by the main Android code
@(export)
g_android_asset_manager: ^AAssetManager

// C wrapper functions from android_main.c
foreign {
    @(link_name="android_asset_open")
    android_asset_open :: proc(filename: cstring, mode: c.int) -> rawptr ---
    @(link_name="android_asset_read")
    android_asset_read :: proc(asset: rawptr, buf: rawptr, count: c.size_t) -> c.int ---
    @(link_name="android_asset_get_length")
    android_asset_get_length :: proc(asset: rawptr) -> c.long ---
    @(link_name="android_asset_close")
    android_asset_close :: proc(asset: rawptr) ---
}

// Android-specific file reading implementation
android_read_entire_file :: proc(file_name: string, allocator := context.allocator) -> (data: []byte, ok: bool) {
    log.infof("android_read_entire_file called for: %s", file_name)
    
    // Android asset loading path
    // Convert to C string
    cfilename := make([]u8, len(file_name)+1, context.temp_allocator)
    copy(cfilename, file_name)
    cfilename[len(file_name)] = 0

    asset_path := cstring(raw_data(cfilename))

    // Android AssetManager doesn't want the "assets/" prefix
    if len(file_name) >= 7 && file_name[:7] == "assets/" {
        asset_path = cstring(raw_data(cfilename[7:]))
    }
    
    // Open the asset
    asset := android_asset_open(asset_path, AASSET_MODE_BUFFER)
    if asset == nil {
        log.errorf("Failed to open asset: %s", file_name)
        return nil, false
    }
    defer android_asset_close(asset)
    
    // Get the file size
    length := android_asset_get_length(asset)
    if length <= 0 {
        log.errorf("Invalid asset length: %d", length)
        return nil, false
    }
    
    // Allocate memory for the file data
    data = make([]byte, int(length), allocator)
    if data == nil {
        log.error("Failed to allocate memory for asset data")
        return nil, false
    }
    
    // Read the entire file
    bytes_read := android_asset_read(asset, raw_data(data), c.size_t(length))
    if bytes_read != c.int(length) {
        log.errorf("Failed to read entire asset. Expected %d bytes, got %d", length, bytes_read)
        delete(data, allocator)
        return nil, false
    }
    
    return data, true
}

// Called from android_main.c
@(export)
odin_android_init :: proc "c" () {
	// Initialize Odin context
	context = runtime.default_context()
	
	mode: int = 0
	when ODIN_OS == .Linux {  // Android is Linux-based
		mode = os.S_IRUSR | os.S_IWUSR | os.S_IRGRP | os.S_IROTH
	}

	// Try to create a log file
	logh, logh_err := os.open("/data/data/com.toyengine.game/files/log.txt", (os.O_CREATE | os.O_TRUNC | os.O_RDWR), mode)

	if logh_err == os.ERROR_NONE {
		os.stdout = logh
		os.stderr = logh
	}

	logger_alloc := context.allocator
	logger := logh_err == os.ERROR_NONE ? log.create_file_logger(logh, allocator = logger_alloc) : log.create_console_logger(allocator = logger_alloc)
	context.logger = logger
	custom_context = context

	when USE_TRACKING_ALLOCATOR {
		default_allocator := context.allocator
		tracking_allocator: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking_allocator, default_allocator)
		context.allocator = mem.tracking_allocator(&tracking_allocator)
	}

	log.info("odin_android_init: Starting initialization")
	log.info("odin_android_init: Context initialized")
	log.info("odin_android_init: Logger initialized")
	
	// Set the custom file reader for glTF2 package
	gltf.set_file_reader(android_read_entire_file)
	log.info("odin_android_init: Set custom file reader for glTF2")
	
	// Test asset loading
	log.info("odin_android_init: Testing asset loading...")
	test_data, test_ok := android_read_entire_file("assets/test.txt")
	if test_ok {
		log.info("odin_android_init: Asset test successful! Read %d bytes", len(test_data))
		log.info("odin_android_init: Content: %s", string(test_data))
		delete(test_data)
	} else {
		log.error("odin_android_init: Asset test failed!")
	}

	// Initialize the game
	log.info("odin_android_init: Calling game_init...")
	game.game_init()
	log.info("odin_android_init: game_init completed successfully")
}

@(export)
odin_android_frame :: proc "c" () {
	context = custom_context
	
	game.game_frame()
}

@(export)
odin_android_cleanup :: proc "c" () {
	context = custom_context
	game.game_cleanup()
	
	free_all(context.temp_allocator)

	when USE_TRACKING_ALLOCATOR {
		// Log memory leaks if tracking allocator is enabled
		tracking_allocator := cast(^mem.Tracking_Allocator)context.allocator.data
		for _, value in tracking_allocator.allocation_map {
			log.errorf("%v: Leaked %v bytes\n", value.location, value.size)
		}
		mem.tracking_allocator_destroy(tracking_allocator)
	}
}

// For now, we'll handle events differently on Android
@(export)
odin_android_touch :: proc "c" (x: f32, y: f32, action: i32) {
	context = custom_context
	
	// Create a fake sapp event for touch
	event: sapp.Event
	
	switch action {
	case 0: // DOWN
		event.type = .TOUCHES_BEGAN
		event.num_touches = 1
		event.touches[0].pos_x = x
		event.touches[0].pos_y = y
		event.touches[0].changed = true
		log.infof("Touch down at %.1f, %.1f", x, y)
		
	case 1: // UP
		event.type = .TOUCHES_ENDED
		event.num_touches = 1
		event.touches[0].pos_x = x
		event.touches[0].pos_y = y
		event.touches[0].changed = true
		log.infof("Touch up at %.1f, %.1f", x, y)
		
	case 2: // MOVE
		event.type = .TOUCHES_MOVED
		event.num_touches = 1
		event.touches[0].pos_x = x
		event.touches[0].pos_y = y
		event.touches[0].changed = true
	}
	
	// Forward to game event handler
	game.game_event(&event)
}

// Export these for GPU selection on Android devices
@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1

// Called from android_main.c to set the asset manager
@(export)
odin_android_set_asset_manager :: proc "c" (mgr: rawptr) {
	// Set a simple context for logging first
	context = runtime.default_context()
	
	log.info("odin_android_set_asset_manager called with mgr=%p", mgr)
	
	if mgr == nil {
		log.error("Asset manager is nil!")
	} else {
		g_android_asset_manager = cast(^AAssetManager)mgr
		log.info("Asset manager set successfully: %p", g_android_asset_manager)
	}
} 