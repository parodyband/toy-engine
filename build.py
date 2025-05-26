#!/usr/bin/env python3

import argparse
import urllib.request
import os
import zipfile
import shutil
import platform
import subprocess
import functools
import webbrowser
import time
import sys
import stat
from enum import Enum
import glob
import re
import hashlib

args_parser = argparse.ArgumentParser(
	prog = "build.py",
	description = "ToyEngine Build Script",
	epilog = "Made by Austin Crane")

args_parser.add_argument("-hot-reload",        action="store_true",   help="Build hot reload game DLL. Also builds executable if game not already running. If the game is running, it will hot reload the game DLL.")
args_parser.add_argument("-release",           action="store_true",   help="Build release game executable. Note: Deletes everything in the 'build/release' directory to make sure you get a clean release.")
args_parser.add_argument("-update-sokol",      action="store_true",   help="Download latest Sokol bindings and latest Sokol shader compiler. Happens automatically when the 'sokol-shdc' and 'source/lib/sokol' directories are missing. Note: Deletes everything in 'sokol-shdc' and 'source/lib/sokol' directories. Also causes -compile-sokol to happen.")
args_parser.add_argument("-compile-sokol",     action="store_true",   help="Compile Sokol C libraries for the current platform. Also compile web (WASM) libraries if emscripten is found (optional). Use -emsdk-path to point out emscripten SDK if not in PATH.")
args_parser.add_argument("-run",               action="store_true",   help="Run the executable after compiling it. For web builds, starts a local server and opens in browser.")
args_parser.add_argument("-debug",             action="store_true",   help="Create debuggable binaries. Makes it possible to debug hot reload and release build in a debugger. For the web build it means that better error messages are printed to console. Debug mode comes with a performance penalty.")
args_parser.add_argument("-no-shader-compile", action="store_true",   help="Don't compile shaders.")
args_parser.add_argument("-shaders",           action="store_true",   help="Compile shaders only. Useful for quick shader iteration.")
args_parser.add_argument("-web",               action="store_true",   help="Build web release. Make sure emscripten (emcc) is in your PATH or use -emsdk-path flag to specify where it lives.")
args_parser.add_argument("-port",              type=int, default=8000, help="Port to use when serving web builds with -run. Default is 8000.")
args_parser.add_argument("-capture",           action="store_true",   help="Build and run with RenderDoc capture (Windows only). Automatically captures a frame and opens in RenderDoc.")
args_parser.add_argument("-emsdk-path",                               help="Path to where you have emscripten installed. Should be the root directory of your emscripten installation. Not necessary if emscripten is in your PATH. Can be used with both -web and -compile-sokol (the latter needs it when building the Sokol web (WASM) libraries).")
args_parser.add_argument("-gl",                action="store_true",   help="Force OpenGL Sokol backend. Useful on some older computers, for example old MacBooks that don't support Metal.")

args = args_parser.parse_args()

num_build_modes = 0
if args.hot_reload:
	num_build_modes += 1
if args.release:
	num_build_modes += 1
if args.web:
	num_build_modes += 1
if args.capture:
	num_build_modes += 1

if num_build_modes > 1:
	print("Can only use one of: -hot-reload, -release, -web and -capture.")
	exit(1)
elif num_build_modes == 0 and not args.update_sokol and not args.compile_sokol and not args.shaders:
	print("You must use one of: -hot-reload, -release, -web, -capture, -update-sokol, -compile-sokol or -shaders.")
	exit(1)

SYSTEM = platform.system()
IS_WINDOWS = SYSTEM == "Windows"
IS_OSX = SYSTEM == "Darwin"
IS_LINUX = SYSTEM == "Linux"

assert IS_WINDOWS or IS_OSX or IS_LINUX, "Unsupported platform."

def main():
	do_update = args.update_sokol

	# Looks like a fresh setup, no sokol anywhere! Trigger automatic update.
	if not os.path.exists(SOKOL_PATH) and not os.path.exists(SOKOL_SHDC_PATH):
		do_update = True

	if do_update:
		update_sokol()

	do_compile = do_update or args.compile_sokol

	if do_compile:
		compile_sokol()

	if not args.no_shader_compile or args.shaders:
		build_shaders()
	
	# If we're only building shaders, we're done
	if args.shaders:
		return

	exe_path = ""
	
	if args.release:
		exe_path = build_release()
	elif args.web:
		exe_path = build_web()
	elif args.hot_reload:
		exe_path = build_hot_reload()
	elif args.capture:
		# Build release for capture
		exe_path = build_release()
		if IS_WINDOWS:
			run_with_renderdoc_capture(exe_path)
		else:
			print("RenderDoc capture is only supported on Windows.")
			return
	
	if exe_path != "" and args.run:
		if args.web:
			# For web builds, start a Python HTTP server and open browser
			print(f"Starting web server in {exe_path}...")
			os.chdir(exe_path)
			
			# Start the server in a subprocess
			port = args.port
			server_process = None
			max_port_attempts = 10
			
			# Try to find an available port
			for port_attempt in range(max_port_attempts):
				try:
					server_process = subprocess.Popen([sys.executable, "-m", "http.server", str(port)], 
													 stderr=subprocess.PIPE, stdout=subprocess.PIPE)
					# Give the server a moment to start
					time.sleep(0.5)
					
					# Check if the process is still running
					if server_process.poll() is None:
						# Server started successfully
						break
					else:
						# Server failed to start, try next port
						port += 1
				except:
					port += 1
			
			if server_process is None or server_process.poll() is not None:
				print(f"Failed to start server. Ports {args.port} to {port} appear to be in use.")
				exit(1)
			
			# Open the browser
			url = f"http://localhost:{port}/index.html"
			print(f"Opening {url} in browser...")
			webbrowser.open(url)
			
			# Keep the script running
			try:
				print(f"Server running at {url}")
				print("Press Ctrl+C to stop the server")
				server_process.wait()
			except KeyboardInterrupt:
				print("\nStopping server...")
				server_process.terminate()
		else:
			# For regular executables
			print("Starting " + exe_path)
			# Get the absolute path of the executable
			exe_abs_path = os.path.abspath(exe_path)
			exe_dir = os.path.dirname(exe_abs_path)
			
			# Verify the executable exists and is executable
			if not os.path.exists(exe_abs_path):
				print(f"Error: Executable not found: {exe_abs_path}")
				exit(1)
			
			if IS_LINUX or IS_OSX:
				if not os.access(exe_abs_path, os.X_OK):
					print(f"Error: Executable is not executable: {exe_abs_path}")
					print("Trying to fix permissions...")
					make_executable(exe_abs_path)
			
			try:
				# Run the executable from its own directory so it can find relative files like dylibs
				print(f"Launching: {exe_abs_path}")
				print(f"Working directory: {exe_dir}")
				
				# On Unix systems, properly detach the process from the parent
				# This prevents VS Code from killing it when the task completes
				if IS_LINUX or IS_OSX:
					process = subprocess.Popen(
						[exe_abs_path], 
						cwd=exe_dir,
						stdout=subprocess.DEVNULL,
						stderr=subprocess.DEVNULL,
						stdin=subprocess.DEVNULL,
						start_new_session=True  # Creates a new process group
					)
				else:
					# Windows
					process = subprocess.Popen([exe_abs_path], cwd=exe_dir)
					
				print(f"Game started with PID: {process.pid}")
				
			except FileNotFoundError as e:
				error_msg = f"Error: Could not find executable: {e}"
				print(error_msg)
				exit(1)
			except PermissionError as e:
				error_msg = f"Error: Permission denied when trying to run executable: {e}"
				print(error_msg)
				print("Make sure the file has execute permissions.")
				exit(1)
			except Exception as e:
				error_msg = f"Error starting executable: {e}"
				print(error_msg)
				exit(1)

def run_with_renderdoc_capture(exe_path):
	"""Build and run the game with RenderDoc capture (Windows only)"""
	captures_dir = "captures"
	if not os.path.exists(captures_dir):
		make_dirs(captures_dir)
	
	# Launch the game and get its PID
	print(f"Launching {exe_path}...")
	game_dir = os.path.dirname(exe_path)
	
	# Use CREATE_NEW_CONSOLE to ensure the game gets its own window
	creation_flags = 0
	if IS_WINDOWS:
		# CREATE_NEW_CONSOLE = 0x00000010
		creation_flags = 0x00000010

	try:
		game_process = subprocess.Popen([exe_path], cwd=game_dir, creationflags=creation_flags)
	except Exception as e:
		print(f"Failed to launch game: {e}")
		return
	
	# Inject RenderDoc as quickly as possible - minimal delay
	print(f"Game launched with PID {game_process.pid}")
	time.sleep(0.1)  # Just 100ms to ensure process has started
	
	# Inject RenderDoc immediately
	renderdoc_cmd = r"C:\Program Files\RenderDoc\renderdoccmd.exe"
	if not os.path.exists(renderdoc_cmd):
		print("RenderDoc not found at expected location: " + renderdoc_cmd)
		print("Please install RenderDoc or update the path in the script.")
		game_process.terminate()
		return
	
	# Use absolute path for capture file
	capture_file = os.path.abspath(os.path.join(captures_dir, "ToyGame.rdc"))
	print(f"Injecting RenderDoc into process ID {game_process.pid}...")
	
	# Use subprocess without shell=True to avoid issues with spaces in paths
	inject_cmd = [renderdoc_cmd, "inject", "--PID", str(game_process.pid), "--capture-file", capture_file]
	result = subprocess.run(inject_cmd, capture_output=True, text=True)
	
	# Check the output to determine if injection was successful
	if result.stdout and "Injecting into PID" in result.stdout:
		print("RenderDoc injection successful")
		if "Launched as ID" in result.stdout:
			# This is actually a success message from RenderDoc
			print(result.stdout.strip())
	else:
		print(f"RenderDoc injection may have failed")
		if result.stderr:
			print(f"Error: {result.stderr}")
		if result.stdout:
			print(f"Output: {result.stdout}")
		
		# Check if the game is still running after injection attempt
		if game_process.poll() is not None:
			print("Game exited after injection attempt.")
			return

	# Wait for game to exit
	print("Waiting for game to exit...")
	game_process.wait()
	
	# Find the latest .rdc file
	print("Done. Capture(s) saved to captures folder.")
	print("Opening latest capture in RenderDoc...")
	rdc_files = glob.glob(os.path.join(captures_dir, "*.rdc"))
	
	if rdc_files:
		latest_rdc = max(rdc_files, key=os.path.getmtime)
		qrenderdoc = r"C:\Program Files\RenderDoc\qrenderdoc.exe"
		if os.path.exists(qrenderdoc):
			subprocess.Popen([qrenderdoc, latest_rdc])
		else:
			print("RenderDoc UI not found at: " + qrenderdoc)
	else:
		print("No .rdc files found in captures folder.")

def preprocess_shader(shader_path, processed_files=None, include_stack=None, include_guards=None):
	"""
	Preprocesses a GLSL shader file by resolving #import statements
	
	Features:
	- Circular dependency detection
	- Include guards (#pragma once or #ifndef style)
	- Relative path resolution
	- Clear error messages with include stack trace
	"""
	if processed_files is None:
		processed_files = {}  # Maps path -> content hash
	if include_stack is None:
		include_stack = []
	if include_guards is None:
		include_guards = set()
	
	# Normalize the path
	shader_path = os.path.normpath(shader_path)
	
	# Check for circular imports
	if shader_path in include_stack:
		error_msg = f"Circular import detected:\n"
		for i, path in enumerate(include_stack):
			error_msg += f"  {'  ' * i}-> {path}\n"
		error_msg += f"  {'  ' * len(include_stack)}-> {shader_path} (circular reference)"
		raise Exception(error_msg)
	
	# Add to include stack
	include_stack.append(shader_path)
	
	try:
		# Read the shader file
		if not os.path.exists(shader_path):
			raise FileNotFoundError(f"Shader file not found: {shader_path}")
		
		with open(shader_path, 'r', encoding='utf-8') as f:
			content = f.read()
		
		# Check if this file uses include guards
		lines = content.splitlines(keepends=True)
		output_lines = []
		
		# Track if we should process this file (for include guards)
		should_process = True
		guard_name = None
		uses_pragma_once = False
		
		# Check for #pragma once at the beginning of the file
		for line in lines:
			stripped = line.strip()
			if not stripped or stripped.startswith('//'):
				continue
			if stripped == '#pragma once':
				uses_pragma_once = True
				guard_name = shader_path  # Use file path as unique identifier
				if guard_name in include_guards:
					should_process = False
				else:
					include_guards.add(guard_name)
			break
		
		if not should_process:
			include_stack.pop()
			return f"// File already included: {os.path.basename(shader_path)}\n"
		
		# Process the file line by line
		i = 0
		while i < len(lines):
			line = lines[i]
			stripped = line.strip()
			
			# Handle #import statements
			if stripped.startswith('#import'):
				# Extract the import path using regex to handle both "path" and <path>
				import_match = re.match(r'#import\s+["<]([^">]+)[">]', stripped)
				if not import_match:
					raise SyntaxError(f"Invalid #import syntax in {shader_path} at line {i+1}: {stripped}")
				
				import_path = import_match.group(1)
				
				# Resolve the import path relative to the current file's directory
				current_dir = os.path.dirname(shader_path)
				resolved_path = os.path.normpath(os.path.join(current_dir, import_path))
				
				# Check if file has already been processed (by content hash)
				if resolved_path in processed_files:
					output_lines.append(f"// Already imported: {import_path}\n")
				else:
					# Add import comment
					output_lines.append(f"\n// BEGIN IMPORT: {import_path} (from {os.path.basename(shader_path)})\n")
					
					# Recursively process the imported file
					try:
						imported_content = preprocess_shader(resolved_path, processed_files, include_stack.copy(), include_guards)
						output_lines.append(imported_content)
						
						# Calculate and store content hash
						content_hash = hashlib.md5(imported_content.encode()).hexdigest()
						processed_files[resolved_path] = content_hash
						
					except Exception as e:
						# Re-raise with context
						raise Exception(f"Error importing '{import_path}' from {shader_path}:\n{str(e)}")
					
					output_lines.append(f"// END IMPORT: {import_path}\n\n")
			
			# Handle traditional include guards (#ifndef, #define, #endif)
			elif stripped.startswith('#ifndef') and i + 1 < len(lines):
				# Check if this is an include guard pattern
				guard_match = re.match(r'#ifndef\s+(\w+)', stripped)
				if guard_match:
					potential_guard = guard_match.group(1)
					next_line = lines[i + 1].strip()
					if next_line == f'#define {potential_guard}':
						# This looks like an include guard
						if potential_guard in include_guards:
							# Skip to the matching #endif
							endif_count = 1
							j = i + 2
							while j < len(lines) and endif_count > 0:
								if lines[j].strip().startswith('#if'):
									endif_count += 1
								elif lines[j].strip().startswith('#endif'):
									endif_count -= 1
								j += 1
							include_stack.pop()
							return f"// File already included (guard: {potential_guard})\n"
						else:
							include_guards.add(potential_guard)
							output_lines.append(line)
					else:
						output_lines.append(line)
				else:
					output_lines.append(line)
			
			else:
				# Regular line, just append
				output_lines.append(line)
			
			i += 1
		
		result = ''.join(output_lines)
		
		# Remove from include stack
		include_stack.pop()
		
		return result
		
	except Exception as e:
		# Remove from include stack before re-raising
		if include_stack and include_stack[-1] == shader_path:
			include_stack.pop()
		raise

def build_shaders():
	print("Building shaders...")
	shdc = get_shader_compiler()

	shaders = []

	for root, dirs, files in os.walk("source"):
		for file in files:
			if file.endswith(".glsl"):
				filepath = os.path.join(root, file)
				
				# Check if this is a main shader file (has @program directive)
				# or a utility file (has #pragma once or no @program)
				with open(filepath, 'r', encoding='utf-8') as f:
					content = f.read()
					
				# Skip files that are utility/import-only files
				# These typically have #pragma once or don't have @program directive
				if '#pragma once' in content:
					print(f"Skipping utility file: {filepath}")
					continue
					
				# Only compile files that have Sokol shader program definitions
				if '@program' not in content:
					print(f"Skipping non-program shader: {filepath}")
					continue
				
				shaders.append(filepath)

	for s in shaders:
		out_dir = os.path.dirname(s)
		out_filename = os.path.basename(s)
		
		# First preprocess the shader to handle imports
		try:
			print(f"Preprocessing {s}...")
			preprocessed_content = preprocess_shader(s)
			
			# Write preprocessed content to a temporary file
			temp_file = s + ".preprocessed"
			with open(temp_file, 'w', encoding='utf-8') as f:
				f.write(preprocessed_content)
			
			# Compile the preprocessed shader
			out = out_dir + "/gen__" + (out_filename.removesuffix("glsl") + "odin")
			
			langs = ""
			
			if args.web:
				langs = "glsl300es"
			elif IS_WINDOWS:
				langs = "hlsl5"
			elif IS_LINUX:
				langs = "glsl430"
			elif IS_OSX:
				langs = "glsl410" if args.gl else "metal_macos"
			
			# Compile the preprocessed file
			execute(shdc + " -i %s -o %s -l %s -f sokol_odin" % (temp_file, out, langs))
			
			# Clean up temporary file
			os.remove(temp_file)
			
		except Exception as e:
			print(f"Error processing shader {s}:")
			print(str(e))
			exit(1)

def get_shader_compiler():
	path = ""

	arch = platform.machine()

	if IS_WINDOWS:
		path = "sokol-shdc\\win32\\sokol-shdc.exe"
	elif IS_LINUX:
		if "arm64" in arch or "aarch64" in arch:
			path = "sokol-shdc/linux_arm64/sokol-shdc"
		else:
			path = "sokol-shdc/linux/sokol-shdc"
	elif IS_OSX:
		if "arm64" in arch or "aarch64" in arch:
			path = "sokol-shdc/osx_arm64/sokol-shdc"
		else:
			path = "sokol-shdc/osx/sokol-shdc"

	assert os.path.exists(path), "Could not find shader compiler. Try running this script with update-sokol parameter"
	return path

path_join = os.path.join


def build_hot_reload():
	out_dir = "build/hot_reload"

	if not os.path.exists(out_dir):
		make_dirs(out_dir)

	exe = out_dir + "/game_hot_reload" + executable_extension()
	dll_final_name = out_dir + "/game" + dll_extension()
	dll = dll_final_name

	if IS_LINUX or IS_OSX:
		dll = out_dir + "/game_tmp" + dll_extension()

	# Only used on windows
	pdb_dir = out_dir + "/game_pdbs"
	pdb_number = 0
	
	dll_extra_args = ""

	if args.debug:
		dll_extra_args += " -debug"

	if args.gl:
		dll_extra_args += " -define:SOKOL_USE_GL=true"

	game_running = process_exists(os.path.basename(exe))

	if IS_WINDOWS:
		if not game_running:
			out_dir_files = os.listdir(out_dir)

			for f in out_dir_files:
				if f.endswith(".dll"):
					try:
						os.remove(os.path.join(out_dir, f))
					except PermissionError:
						# File is in use, skip it
						pass

			if os.path.exists(pdb_dir):
				shutil.rmtree(pdb_dir)

		if not os.path.exists(pdb_dir):
			make_dirs(pdb_dir)
		else:
			pdb_files = os.listdir(pdb_dir)

			for f in pdb_files:
				if f.endswith(".pdb"):
					n = int(f.removesuffix(".pdb").removeprefix("game_"))

					if n > pdb_number:
						pdb_number = n

		# On windows we make sure the PDB name for the DLL is unique on each
		# build. This makes debugging work properly.
		dll_extra_args += " -pdb-name:%s/game_%i.pdb" % (pdb_dir, pdb_number + 1)

		dll_name = "sokol_dll_windows_x64_d3d11_debug.dll" if args.debug else "sokol_dll_windows_x64_d3d11_release.dll"
		dll_dest = out_dir + "/" + dll_name

		if not os.path.exists(dll_dest):
			print("Copying %s" % dll_name)
			shutil.copyfile(SOKOL_PATH + "/" + dll_name, dll_dest)

	print("Building " + dll_final_name + "...")
	execute("odin build source -define:SOKOL_DLL=true -build-mode:dll -out:%s %s" % (dll, dll_extra_args))

	if IS_LINUX or IS_OSX:
		os.rename(dll, dll_final_name)

	if game_running:
		print("Hot reloading...")

		# Hot reloading means the running executable will see the new dll.
		# So we can just return empty string here. This makes sure that the main
		# function does not try to run the executable, even if `run` is specified.
		return ""

	exe_extra_args = ""

	if IS_WINDOWS:
		exe_extra_args += " -pdb-name:%s/main_hot_reload.pdb" % out_dir

	if args.debug:
		exe_extra_args += " -debug"

	if args.gl:
		exe_extra_args += " -define:SOKOL_USE_GL=true"

	print("Building " + exe + "...")
	execute("odin build source/lib/main_hot_reload -strict-style -define:SOKOL_DLL=true -vet -out:%s %s" % (exe, exe_extra_args))

	# Make executable on Unix-like systems
	make_executable(exe)

	if IS_OSX:
		dylib_folder = "source/lib/sokol/dylib"

		if not os.path.exists(dylib_folder):
			print("Dynamic libraries for OSX don't seem to be built. Please re-run 'build.py -compile-sokol'.")
			exit(1)

		dylib_out_dir = out_dir + "/dylib"
		if not os.path.exists(dylib_out_dir):
			os.mkdir(dylib_out_dir)

		dylibs = os.listdir(dylib_folder)

		for d in dylibs:
			src = "%s/%s" % (dylib_folder, d)
			dest = "%s/%s" % (dylib_out_dir, d)
			do_copy = False

			if not os.path.exists(dest):
				do_copy = True
			elif os.path.getsize(dest) != os.path.getsize(src):
				do_copy = True

			if do_copy:
				print("Copying %s to %s" % (src, dest))
				shutil.copyfile(src, dest)

	# Copy assets folder to the build directory
	assets_src = "assets"
	assets_dest = out_dir + "/assets"
	if os.path.exists(assets_src):
		# Only copy if source exists and destination doesn't exist or is outdated
		if not os.path.exists(assets_dest) or not game_running:
			if os.path.exists(assets_dest):
				shutil.rmtree(assets_dest)
			print("Copying assets folder...")
			shutil.copytree(assets_src, assets_dest)

	return exe

def build_release():
	out_dir = "build/release"

	if os.path.exists(out_dir):
		shutil.rmtree(out_dir)

	make_dirs(out_dir)

	exe = out_dir + "/game_release" + executable_extension()

	print("Building " + exe + "...")

	extra_args = ""

	if not args.debug:
		extra_args += " -no-bounds-check -o:speed"

		if IS_WINDOWS:
			extra_args += " -subsystem:windows"
	else:
		extra_args += " -debug"

	if args.gl:
		extra_args += " -define:SOKOL_USE_GL=true"

	execute("odin build source/lib/main_release -out:%s -strict-style -vet %s" % (exe, extra_args))
	
	# Make executable on Unix-like systems
	make_executable(exe)
	
	shutil.copytree("assets", out_dir + "/assets")

	return exe

def build_web():
	out_dir = "build/web"
	make_dirs(out_dir)

	odin_extra_args = ""

	if args.debug:
		odin_extra_args += " -debug"

	print("Building js_wasm32 game object...")
	execute("odin build source/lib/main_web -target:js_wasm32 -build-mode:obj -vet -strict-style -out:%s/game %s" % (out_dir, odin_extra_args))
	odin_path = subprocess.run(["odin", "root"], capture_output=True, text=True).stdout

	shutil.copyfile(os.path.join(odin_path, "core/sys/wasm/js/odin.js"), os.path.join(out_dir, "odin.js"))
	os.environ["EMSDK_QUIET"] = "1"

	wasm_lib_suffix = "debug.a" if args.debug else "release.a"

	emcc_files = [
		"%s/game.wasm.o" % out_dir,
		"source/lib/sokol/app/sokol_app_wasm_gl_" + wasm_lib_suffix,
		"source/lib/sokol/glue/sokol_glue_wasm_gl_" + wasm_lib_suffix,
		"source/lib/sokol/gfx/sokol_gfx_wasm_gl_" + wasm_lib_suffix,
		"source/lib/sokol/shape/sokol_shape_wasm_gl_" + wasm_lib_suffix,
		"source/lib/sokol/log/sokol_log_wasm_gl_" + wasm_lib_suffix,
		"source/lib/sokol/gl/sokol_gl_wasm_gl_" + wasm_lib_suffix,
	]

	emcc_files_str = " ".join(emcc_files)

	# Note --preload-file assets, this bakes in the whole assets directory into
	# the web build.
	emcc_flags = "--shell-file source/lib/web/index_template.html --preload-file assets -sWASM_BIGINT -sWARN_ON_UNDEFINED_SYMBOLS=0 -sMAX_WEBGL_VERSION=2 -sASSERTIONS -sALLOW_MEMORY_GROWTH=1 -sINITIAL_HEAP=16777216 -sSTACK_SIZE=65536"

	build_flags = ""

	# -g is the emcc debug flag, it makes the errors in the browser console better.
	if args.debug:
		build_flags += " -g "

	emcc_command = "emcc %s -o %s/index.html %s %s" % (build_flags, out_dir, emcc_files_str, emcc_flags)

	emsdk_env = get_emscripten_env_command()

	if emsdk_env:
		if IS_WINDOWS:
			emcc_command = emsdk_env + " && " + emcc_command
		else:
			emcc_command = "bash -c \"" + emsdk_env + " && " + emcc_command + "\""
	else:
		if shutil.which("emcc") is None:
			print("Could not find emcc. Try providing emscripten SDK path using '-emsdk-path PATH' or run the emsdk_env script inside the emscripten folder before running this script.")
			exit(1)

	print("Building web application using emscripten to %s..." % out_dir)
	execute(emcc_command)

	# Not needed
	os.remove(os.path.join(out_dir, "game.wasm.o"))
	
	# Return the build directory so -run can work with web builds
	return out_dir

def execute(cmd):
	res = os.system(cmd)
	if res != 0:
		print("Failed running:" + cmd)
		exit(1)

def dll_extension():
	if IS_WINDOWS:
		return ".dll"

	if IS_OSX:
		return ".dylib"

	return ".so"

def executable_extension():
	if IS_WINDOWS:
		return ".exe"

	return ".bin"

SOKOL_PATH = "source/lib/sokol"
SOKOL_SHDC_PATH = "sokol-shdc"

def update_sokol():
	def update_sokol_bindings():
		SOKOL_ZIP_URL = "https://github.com/floooh/sokol-odin/archive/refs/heads/main.zip"

		if os.path.exists(SOKOL_PATH):
			shutil.rmtree(SOKOL_PATH)

		temp_zip = "sokol-temp.zip"
		temp_folder = "sokol-temp"
		print("Downloading Sokol Odin bindings to directory source/lib/sokol...")
		urllib.request.urlretrieve(SOKOL_ZIP_URL, temp_zip)

		with zipfile.ZipFile(temp_zip) as zip_file:
			zip_file.extractall(temp_folder)
			shutil.copytree(temp_folder + "/sokol-odin-main/sokol", SOKOL_PATH)

		os.remove(temp_zip)
		shutil.rmtree(temp_folder)

	def update_sokol_shdc():
		if os.path.exists(SOKOL_SHDC_PATH):
			shutil.rmtree(SOKOL_SHDC_PATH)

		TOOLS_ZIP_URL = "https://github.com/floooh/sokol-tools-bin/archive/refs/heads/master.zip"
		temp_zip = "sokol-tools-temp.zip"
		temp_folder = "sokol-tools-temp"

		print("Downloading Sokol Shader Compiler to directory sokol-shdc...")
		urllib.request.urlretrieve(TOOLS_ZIP_URL, temp_zip)

		with zipfile.ZipFile(temp_zip) as zip_file:
			zip_file.extractall(temp_folder)
			shutil.copytree(temp_folder + "/sokol-tools-bin-master/bin", SOKOL_SHDC_PATH)

		if IS_LINUX:
			execute("chmod +x sokol-shdc/linux/sokol-shdc")
			execute("chmod +x sokol-shdc/linux_arm64/sokol-shdc")

		if IS_OSX:
			execute("chmod +x sokol-shdc/osx/sokol-shdc")
			execute("chmod +x sokol-shdc/osx_arm64/sokol-shdc")

		os.remove(temp_zip)
		shutil.rmtree(temp_folder)

	update_sokol_bindings()
	update_sokol_shdc()

def compile_sokol():
	owd = os.getcwd()
	os.chdir(SOKOL_PATH)

	emsdk_env = get_emscripten_env_command()
	
	print("Building Sokol C libraries...")

	if IS_WINDOWS:
		if shutil.which("cl.exe") is not None:
			execute("build_clibs_windows.cmd")
		else:
			print("cl.exe not in PATH. Try re-running build.py with flag -compile-sokol from a Visual Studio command prompt.")

		if emsdk_env:
			execute(emsdk_env + " && build_clibs_wasm.bat")
		else:
			if shutil.which("emcc.bat"):
				execute("build_clibs_wasm.bat")
			else:
				print("emcc not in PATH, skipping building of WASM libs. Tip: You can also use -emsdk-path to specify where emscripten lives.")

	elif IS_LINUX:
		execute("bash build_clibs_linux.sh")

		build_wasm_prefix = ""
		if emsdk_env:
			os.environ["EMSDK_QUIET"] = "1"
			build_wasm_prefix += emsdk_env + " && "
		elif shutil.which("emcc") is not None:
			execute("bash -c \"" + build_wasm_prefix + " bash build_clibs_wasm.sh\"")
		else:
			print("emcc not in PATH, skipping building of WASM libs. Tip: You can also use -emsdk-path to specify where emscripten lives.")
		
	elif IS_OSX:
		execute("bash build_clibs_macos.sh")
		execute("bash build_clibs_macos_dylib.sh")
		
		build_wasm_prefix = ""
		if emsdk_env:
			os.environ["EMSDK_QUIET"] = "1"
			build_wasm_prefix += emsdk_env + " && "
		elif shutil.which("emcc") is not None:
			execute("bash -c \"" + build_wasm_prefix + " bash build_clibs_wasm.sh\"")
		else:
			print("emcc not in PATH, skipping building of WASM libs. Tip: You can also use -emsdk-path to specify where emscripten lives.")

	os.chdir(owd)


def get_emscripten_env_command():
	if args.emsdk_path is None:
		return None

	if IS_WINDOWS:
		return os.path.join(args.emsdk_path, "emsdk_env.bat")
	elif IS_LINUX or IS_OSX:
		return "source " + os.path.join(args.emsdk_path, "emsdk_env.sh")

	return None

def process_exists(process_name):
	if IS_WINDOWS:
		call = 'TASKLIST', '/NH', '/FI', 'imagename eq %s' % process_name
		return process_name in str(subprocess.check_output(call))
	else:
		out = subprocess.run(["pgrep", "-f", process_name], capture_output=True, text=True).stdout
		return out != ""


	return False

def make_dirs(path):
	n = os.path.normpath(path)
	s = n.split(os.sep)
	p = ""

	for d in s:
		p = os.path.join(p, d)

		if not os.path.exists(p):
			os.mkdir(p)

def make_executable(file_path):
	"""Make a file executable on Unix-like systems"""
	if IS_LINUX or IS_OSX:
		if os.path.exists(file_path):
			current_permissions = os.stat(file_path).st_mode
			os.chmod(file_path, current_permissions | stat.S_IEXEC)
			print(f"Made {file_path} executable")

print = functools.partial(print, flush=True)

main()