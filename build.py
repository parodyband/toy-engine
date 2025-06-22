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
import threading

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
args_parser.add_argument("-app-name",                                 help="Name for the macOS app bundle (default: ToyGame). Only used when building release on macOS.")
args_parser.add_argument("-android",           action="store_true",   help="Build Android APK release.")
args_parser.add_argument("-android-sdk-path",  help="Path to Android SDK. If not provided, it will check for ANDROID_HOME environment variable.")
args_parser.add_argument("-android-ndk-path",  help="Path to Android NDK. If not provided, it will check for ANDROID_NDK_HOME environment variable.")

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
if args.android:
	num_build_modes += 1

if num_build_modes > 1:
	print("Can only use one of: -hot-reload, -release, -web, -capture or -android.")
	exit(1)
elif num_build_modes == 0 and not args.update_sokol and not args.compile_sokol and not args.shaders:
	print("You must use one of: -hot-reload, -release, -web, -capture, -android, -update-sokol, -compile-sokol or -shaders.")
	exit(1)

SYSTEM = platform.system()
IS_WINDOWS = SYSTEM == "Windows"
IS_OSX = SYSTEM == "Darwin"
IS_LINUX = SYSTEM == "Linux"

assert IS_WINDOWS or IS_OSX or IS_LINUX, "Unsupported platform."

owd = os.getcwd()

def main():
	global owd
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
	elif args.android:
		exe_path = build_android()
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
		elif args.android:
			# For Android builds, install APK and run the app
			print("Installing and running Android APK...")
			
			# Check if adb is available
			if shutil.which("adb") is None:
				print("Error: adb not found in PATH. Please install Android SDK platform-tools.")
				exit(1)
			
			# Install the APK
			print(f"Installing {exe_path}...")
			install_result = subprocess.run(["adb", "install", "-r", exe_path], capture_output=True, text=True)
			if install_result.returncode != 0:
				print(f"Error installing APK: {install_result.stderr}")
				exit(1)
			print("APK installed successfully.")
			
			# Launch the app
			package_name = "com.toyengine.game"
			activity_name = "android.app.NativeActivity"
			print(f"Launching {package_name}...")
			launch_result = subprocess.run(["adb", "shell", "am", "start", "-n", f"{package_name}/{activity_name}"], 
										  capture_output=True, text=True)
			if launch_result.returncode != 0:
				print(f"Error launching app: {launch_result.stderr}")
				exit(1)
			print("App launched successfully.")
			
			# Clear previous logs
			subprocess.run(["adb", "logcat", "-c"], capture_output=True)
			
			# Tail the logs
			print("\nShowing Android logs (press Ctrl+C to stop):")
			print("-" * 60)
			try:
				# Filter logs by our app's tag
				log_process = subprocess.Popen(["adb", "logcat", "ToyEngine:I", "*:S"], 
											  stdout=subprocess.PIPE, 
											  stderr=subprocess.PIPE,
											  universal_newlines=True,
											  bufsize=1)
				
				# Also capture app logs from the log file
				def tail_app_logs():
					time.sleep(2)  # Give app time to create log file
					while True:
						try:
							# Try to read the app's log file
							log_result = subprocess.run(["adb", "shell", "run-as", package_name, "cat", "files/log.txt"], 
													   capture_output=True, text=True)
							if log_result.returncode == 0 and log_result.stdout:
								# Print new content
								print("\n=== App Log ===")
								print(log_result.stdout)
								print("=" * 60)
							time.sleep(5)  # Check every 5 seconds
						except:
							pass
				
				# Start log tailing in a separate thread
				log_thread = threading.Thread(target=tail_app_logs, daemon=True)
				log_thread.start()
				
				# Read and print logcat output
				for line in log_process.stdout:
					print(line.rstrip())
					
			except KeyboardInterrupt:
				print("\nStopping log output...")
				log_process.terminate()
		else:
			# For regular executables and app bundles
			print("Starting " + exe_path)
			
			# Handle macOS app bundles specially
			if IS_OSX and exe_path.endswith('.app'):
				try:
					print(f"Launching macOS app bundle: {exe_path}")
					process = subprocess.Popen(
						["open", exe_path], 
						stdout=subprocess.DEVNULL,
						stderr=subprocess.DEVNULL,
						stdin=subprocess.DEVNULL,
						start_new_session=True
					)
					print(f"App bundle launched with PID: {process.pid}")
					return
				except Exception as e:
					error_msg = f"Error launching app bundle: {e}"
					print(error_msg)
					exit(1)
			
			# For regular executables
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
	
	# Handle macOS app bundle case (extract actual executable path)
	actual_exe_path = exe_path
	if IS_OSX and exe_path.endswith('.app'):
		# For app bundles, the actual executable is inside Contents/MacOS/
		app_name_base = args.app_name if args.app_name else "ToyGame"
		actual_exe_path = os.path.join(exe_path, "Contents", "MacOS", app_name_base)
		if not os.path.exists(actual_exe_path):
			print(f"Error: Could not find executable inside app bundle: {actual_exe_path}")
			return
	
	# Launch the game and get its PID
	print(f"Launching {actual_exe_path}...")
	game_dir = os.path.dirname(actual_exe_path)
	
	# Use CREATE_NEW_CONSOLE to ensure the game gets its own window
	creation_flags = 0
	if IS_WINDOWS:
		# CREATE_NEW_CONSOLE = 0x00000010
		creation_flags = 0x00000010

	try:
		game_process = subprocess.Popen([actual_exe_path], cwd=game_dir, creationflags=creation_flags)
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
			elif args.android:
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

	# On macOS, create a .app bundle
	if IS_OSX:
		app_name_base = args.app_name if args.app_name else "ToyGame"
		app_name = f"{app_name_base}.app"
		app_bundle_path = os.path.join(out_dir, app_name)
		contents_path = os.path.join(app_bundle_path, "Contents")
		macos_path = os.path.join(contents_path, "MacOS")
		resources_path = os.path.join(contents_path, "Resources")
		
		# Create the .app bundle directory structure
		make_dirs(macos_path)
		make_dirs(resources_path)
		
		# Build the executable (without .bin extension for app bundle)
		exe = os.path.join(macos_path, app_name_base)
	else:
		exe = out_dir + "/game_release" + executable_extension()

	print("Building " + exe + "...")

	extra_args = ""

	if not args.debug:
		extra_args += " -no-bounds-check -o:speed"

	if args.gl:
		extra_args += " -define:SOKOL_USE_GL=true"

	execute("odin build source/lib/main_release -out:%s -strict-style -vet %s" % (exe, extra_args))
	
	# Make executable on Unix-like systems
	make_executable(exe)
	
	if IS_OSX:
		# Create Info.plist for the macOS app bundle
		info_plist_path = os.path.join(contents_path, "Info.plist")
		bundle_identifier = f"com.{app_name_base.lower()}.app"
		info_plist_content = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>{app_name_base}</string>
	<key>CFBundleIdentifier</key>
	<string>{bundle_identifier}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>{app_name_base}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>10.15</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSSupportsAutomaticGraphicsSwitching</key>
	<true/>
</dict>
</plist>'''
		
		with open(info_plist_path, 'w') as f:
			f.write(info_plist_content)
		
		# Copy assets to MacOS folder alongside the executable (not Resources)
		# This way the executable can find them with relative paths
		if os.path.exists("assets"):
			assets_dest = os.path.join(macos_path, "assets")
			shutil.copytree("assets", assets_dest)
		
		print(f"Created macOS app bundle: {app_bundle_path}")
		return app_bundle_path
	else:
		# For non-macOS platforms, copy assets as before
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
		"%s/game.wasm" % out_dir,
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
	os.remove(os.path.join(out_dir, "game.wasm"))
	
	# Return the build directory so -run can work with web builds
	return out_dir

def execute(cmd, env=None):
	"""
	Execute a command. If the command is a list, it's executed directly.
	If it's a string, it's executed through the shell.
	"""
	use_shell = isinstance(cmd, str)
	print(f"Executing: {cmd}")
	res = subprocess.run(cmd, shell=use_shell, env=env)
	if res.returncode != 0:
		print(f"Failed running: {cmd}")
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
	global owd
	os.chdir(SOKOL_PATH)

	emsdk_env = get_emscripten_env_command()
	
	print("Building Sokol C libraries...")

	if IS_WINDOWS:
		# Try to find Visual Studio and set up the environment automatically
		vs_path = r"C:\Program Files\Microsoft Visual Studio\2022\Community"
		vcvars_path = os.path.join(vs_path, "VC", "Auxiliary", "Build", "vcvars64.bat")
		
		if os.path.exists(vcvars_path):
			# Run the build script with vcvars64 environment
			print("Setting up Visual Studio x64 environment...")
			cmd = f'cmd /c "call "{vcvars_path}" && build_clibs_windows.cmd"'
			execute(cmd)
		elif shutil.which("cl.exe") is not None:
			# cl.exe is already in PATH, just run the build script
			execute("build_clibs_windows.cmd")
		else:
			print("Error: Could not find Visual Studio 2022 or cl.exe in PATH.")
			print("Please install Visual Studio 2022 Community or run from a Visual Studio command prompt.")
			os.chdir(owd)
			return

		# Build Android libraries if NDK is available
		ndk_path = get_android_ndk_path()
		if ndk_path and os.path.exists(ndk_path):
			print("Building Sokol Android libraries...")
			build_sokol_android_libs(ndk_path)
		else:
			print("Android NDK not found, skipping Android Sokol library build.")

		if emsdk_env:
			execute(emsdk_env + " && build_clibs_wasm.bat")
		else:
			if shutil.which("emcc.bat"):
				execute("build_clibs_wasm.bat")
			else:
				print("emcc not in PATH, skipping building of WASM libs. Tip: You can also use -emsdk-path to specify where emscripten lives.")

	elif IS_LINUX:
		execute("bash build_clibs_linux.sh")

		# Build Android libraries if NDK is available
		ndk_path = get_android_ndk_path()
		if ndk_path and os.path.exists(ndk_path):
			print("Building Sokol Android libraries...")
			build_sokol_android_libs(ndk_path)
		else:
			print("Android NDK not found, skipping Android Sokol library build.")

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

		# Build Android libraries if NDK is available
		ndk_path = get_android_ndk_path()
		if ndk_path and os.path.exists(ndk_path):
			print("Building Sokol Android libraries...")
			build_sokol_android_libs(ndk_path)
		else:
			print("Android NDK not found, skipping Android Sokol library build.")
		
		build_wasm_prefix = ""
		if emsdk_env:
			os.environ["EMSDK_QUIET"] = "1"
			build_wasm_prefix += emsdk_env + " && "
		elif shutil.which("emcc") is not None:
			execute("bash -c \"" + build_wasm_prefix + " bash build_clibs_wasm.sh\"")
		else:
			print("emcc not in PATH, skipping building of WASM libs. Tip: You can also use -emsdk-path to specify where emscripten lives.")

	os.chdir(owd)

def build_sokol_android_libs(ndk_path):
	"""Build Sokol libraries for Android using the NDK"""
	# Save current directory
	old_cwd = os.getcwd()
	
	# Don't change directory if we're already in the sokol directory
	if not old_cwd.endswith("sokol"):
		os.chdir(SOKOL_PATH)
	
	host_tag = get_host_tag()
	if not host_tag:
		print(f"Unsupported host system for NDK: {SYSTEM}")
		os.chdir(old_cwd)
		return
		
	toolchain_path = os.path.join(ndk_path, "toolchains", "llvm", "prebuilt", host_tag)
	api_level = 26  # Changed from 24 to 26 for AAudio support
	cc_path = os.path.join(toolchain_path, "bin", f"aarch64-linux-android{api_level}-clang")
	ar_path = os.path.join(toolchain_path, "bin", "llvm-ar")
	
	if IS_WINDOWS:
		cc_path += ".cmd"
	
	# Set environment for Android build
	build_env = os.environ.copy()
	build_env["CC"] = cc_path
	build_env["AR"] = ar_path
	
	# Create output directories
	for lib in ["app", "gfx", "gl", "glue", "log", "shape", "audio", "debugtext", "time"]:
		os.makedirs(lib, exist_ok=True)
	
	# Compile each Sokol module for Android
	# Note: sokol_app is excluded because it doesn't support SOKOL_NO_ENTRY on Android
	sokol_modules = [
		# ("app/app.odin", "sokol_app_clib", ["system:log", "system:android", "system:EGL", "system:GLESv3"]),
		("gfx/gfx.odin", "sokol_gfx_clib", ["system:log", "system:android", "system:EGL", "system:GLESv3"]),
		("gl/gl.odin", "sokol_gl_clib", ["system:log", "system:android", "system:EGL", "system:GLESv3"]),
		("glue/glue.odin", "sokol_glue_clib", ["system:log", "system:android"]),
		("log/log.odin", "sokol_log_clib", ["system:log", "system:android"]),
		("shape/shape.odin", "sokol_shape_clib", ["system:log", "system:android", "system:EGL", "system:GLESv3"]),
		("audio/audio.odin", "sokol_audio_clib", ["system:log", "system:android"]),
		("debugtext/debugtext.odin", "sokol_debugtext_clib", ["system:log", "system:android", "system:EGL", "system:GLESv3"]),
		("time/time.odin", "sokol_time_clib", ["system:log", "system:android"]),
	]
	
	for module_path, lib_name, android_libs in sokol_modules:
		# Extract the actual module name (e.g., "app" from "sokol_app_clib")
		module_name = lib_name.replace("sokol_", "").replace("_clib", "")
		print(f"Building {module_name} for Android...")
		
		c_file = f"c/sokol_{module_name}.c"
		if not os.path.exists(c_file):
			print(f"Warning: {c_file} not found, skipping...")
			continue
			
		obj_file = f"{module_name}/sokol_{module_name}_android_arm64_gles3.o"
		lib_file = f"{module_name}/sokol_{module_name}_android_arm64_gles3_release.a"
		
		# Compile flags
		# Use module-specific implementation define
		impl_define = f"-DSOKOL_{module_name.upper()}_IMPL"
		cflags = f"-c -fPIC -O2 -DSOKOL_GLES3 {impl_define}"
		
		# Compile
		compile_cmd = f'"{cc_path}" {cflags} {c_file} -o {obj_file}'
		execute(compile_cmd, env=build_env)
		
		# Create static library
		ar_cmd = f'"{ar_path}" rcs {lib_file} {obj_file}'
		execute(ar_cmd, env=build_env)
		
		# Also create debug version
		lib_file_debug = f"{module_name}/sokol_{module_name}_android_arm64_gles3_debug.a"
		shutil.copy(lib_file, lib_file_debug)
	
	# Create sokol_app stub library for Android from our custom android_stubs.c
	print("Creating sokol_app stub library for Android...")
	
	# The android_stubs.c is in the app subdirectory (we're already in the sokol directory)
	android_stubs_src = "app/android_stubs.c"
	
	if not os.path.exists(android_stubs_src):
		print(f"Error: {android_stubs_src} not found in {os.getcwd()}")
		os.chdir(old_cwd)
		return
		
	# Compile the stubs with visibility default for exported functions
	stubs_obj = "app/sokol_app_android_arm64_gles3.o"
	cflags = "-c -fPIC -O2 -fvisibility=hidden"  # Default visibility is hidden
	execute(f'"{cc_path}" {cflags} {android_stubs_src} -o {stubs_obj}', env=build_env)
	
	# Create static libraries
	for build_type in ["release", "debug"]:
		lib_file = f"app/sokol_app_android_arm64_gles3_{build_type}.a"
		execute(f'"{ar_path}" rcs {lib_file} {stubs_obj}', env=build_env)
	
	print("Android Sokol libraries built successfully!")
	
	# Restore original directory
	os.chdir(old_cwd)


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
	os.makedirs(path, exist_ok=True)

def make_executable(file_path):
	"""Make a file executable on Unix-like systems"""
	if IS_LINUX or IS_OSX:
		if os.path.exists(file_path):
			current_permissions = os.stat(file_path).st_mode
			os.chmod(file_path, current_permissions | stat.S_IEXEC)
			print(f"Made {file_path} executable")

print = functools.partial(print, flush=True)

def get_android_sdk_path():
	if args.android_sdk_path:
		return args.android_sdk_path
	if "ANDROID_HOME" in os.environ:
		return os.environ["ANDROID_HOME"]
	if "ANDROID_SDK_ROOT" in os.environ:
		return os.environ["ANDROID_SDK_ROOT"]
	
	# Check default locations
	if IS_WINDOWS:
		default_path = os.path.expanduser(r"~\AppData\Local\Android\Sdk")
		if os.path.exists(default_path):
			return default_path
	elif IS_LINUX:
		default_path = os.path.expanduser("~/Android/Sdk")
		if os.path.exists(default_path):
			return default_path
	elif IS_OSX:
		default_path = os.path.expanduser("~/Library/Android/sdk")
		if os.path.exists(default_path):
			return default_path
	
	return None

def find_android_sdk():
	"""Find Android SDK path, same as get_android_sdk_path but for clarity"""
	return get_android_sdk_path()

def get_android_ndk_path():
	if args.android_ndk_path:
		return os.path.normpath(args.android_ndk_path)
	if "ANDROID_NDK_HOME" in os.environ:
		return os.path.normpath(os.environ["ANDROID_NDK_HOME"])
	
	sdk_path = get_android_sdk_path()
	if sdk_path:
		ndk_bundle_path = os.path.join(sdk_path, "ndk-bundle")
		if os.path.exists(ndk_bundle_path):
			return ndk_bundle_path
		
		ndk_dir = os.path.join(sdk_path, "ndk")
		if os.path.exists(ndk_dir):
			versions = os.listdir(ndk_dir)
			if versions:
				# Sort by version number
				versions.sort(key=lambda v: list(map(int, v.split('.'))), reverse=True)
				return os.path.join(ndk_dir, versions[0])
	return None

def download_file(url, dest):
	print(f"Downloading {url} to {dest}...")
	try:
		urllib.request.urlretrieve(url, dest)
	except Exception as e:
		print(f"Error downloading {url}: {e}")
		exit(1)

def get_host_tag():
	if IS_WINDOWS:
		return "windows-x86_64"
	elif IS_LINUX:
		return "linux-x86_64"
	elif IS_OSX:
		# ARM-based Macs can run x86_64 NDK binaries via Rosetta 2
		return "darwin-x86_64"
	return None

def build_android():
	global owd
	print("Building for Android...")
	out_dir = os.path.abspath("build/android")
	temp_build_dir = os.path.abspath("build/android_temp")

	def remove_dir_with_retry(path, max_retries=3):
		if not os.path.exists(path): return
		for i in range(max_retries):
			try:
				shutil.rmtree(path)
				return
			except PermissionError as e:
				if i < max_retries - 1:
					print(f"Directory {path} is locked, retrying in 1 second...")
					time.sleep(1)
				else:
					print(f"Warning: Could not remove {path}: {e}")
	
	remove_dir_with_retry(out_dir)
	remove_dir_with_retry(temp_build_dir)
	
	make_dirs(out_dir)
	make_dirs(temp_build_dir)
	
	os.environ['TEMP'] = temp_build_dir
	os.environ['TMP'] = temp_build_dir

	patch_sokol_for_android()

	# 1. Check for NDK
	ndk_path = get_android_ndk_path()
	if not ndk_path or not os.path.exists(ndk_path):
		print("Error: Android NDK not found.")
		exit(1)
	print(f"Using NDK at: {ndk_path}")
	
	app_name = "ToyGame"
	package_name = "com.toyengine.game"
	app_dir = os.path.join(out_dir, "app")
	main_dir = os.path.join(app_dir, "src", "main")
	jni_libs_dir = os.path.join(main_dir, "jniLibs", "arm64-v8a")
	assets_dir = os.path.join(main_dir, "assets")
	
	make_dirs(jni_libs_dir)
	make_dirs(assets_dir)

	print("Compiling Odin code for android_arm64...")
	
	host_tag = get_host_tag()
	if not host_tag:
		print(f"Unsupported host system for NDK: {SYSTEM}")
		exit(1)
		
	toolchain_path = os.path.join(ndk_path, "toolchains", "llvm", "prebuilt", host_tag)
	api_level = 26  # Changed from 24 to 26 for AAudio support
	cc_path = os.path.join(toolchain_path, "bin", f"aarch64-linux-android{api_level}-clang")
	ar_path = os.path.join(toolchain_path, "bin", "llvm-ar")

	if IS_WINDOWS:
		cc_path += ".cmd"
	
	if not os.path.exists(cc_path):
		print(f"Error: NDK C compiler not found at {cc_path}")
		exit(1)

	build_env = os.environ.copy()
	build_env["AR"] = ar_path
	build_env["CC"] = cc_path
	build_env["ODIN_ANDROID_NDK"] = ndk_path

	# Use main_android for Android builds to get the proper exports
	odin_source_path_abs = os.path.abspath("source/lib/main_android")
	
	# Copy all Android Sokol libraries to a central location
	android_libs_dir = os.path.join(out_dir, "libs")
	make_dirs(android_libs_dir)
	
	print("Copying Android libraries...")
	sokol_modules = ["app", "gfx", "gl", "glue", "log", "shape", "audio", "debugtext", "time"]
	copied_libs = []
	build_type = "debug" if args.debug else "release"
	for module in sokol_modules:
		lib_name = f"sokol_{module}_android_arm64_gles3_{build_type}.a"
		src_path = os.path.join(SOKOL_PATH, module, lib_name)
		if os.path.exists(src_path):
			dst_path = os.path.join(android_libs_dir, lib_name)
			shutil.copy2(src_path, dst_path)
			print(f"Copied {lib_name}")
			copied_libs.append(lib_name)

	# Compile the Android entry point
	print("Compiling Android entry point...")
	android_main_src = os.path.join(owd, "source/lib/main_android/android_main.c")
	android_main_obj = os.path.join(out_dir, "android_main.o")
	android_main_lib = os.path.join(android_libs_dir, "android_main.a")
	
	compile_cmd = [
		cc_path,
		"-c", "-fPIC", "-O2",
		f"-I{os.path.join(ndk_path, 'sysroot/usr/include')}",
		f"-I{os.path.join(ndk_path, 'sources/android/native_app_glue')}",
		android_main_src,
		"-o", android_main_obj
	]
	execute(compile_cmd, env=build_env)
	
	# Create a static library from the object file
	ar_cmd = [ar_path, "rcs", android_main_lib, android_main_obj]
	execute(ar_cmd, env=build_env)
	copied_libs.append("android_main.a")
	
	os.chdir(out_dir)

	# Only link android_main.a and Android system libraries
	# The Sokol libraries are already linked via the patched foreign imports
	flags = f"-Llibs -l:android_main.a -landroid -llog -lEGL -lGLESv3"
	extra_linker_flags = f"-extra-linker-flags:{flags}"

	final_lib_name = "libgame.so"

	odin_cmd = [
		"odin", "build", 
		odin_source_path_abs,
		f"-out:libgame.so",
		"-build-mode:shared",
		"-target:linux_arm64",
		"-vet",
		"-define:SOKOL_GLES3=true",
		"-define:ANDROID=true",
		"-subtarget:android",
		f"-extra-linker-flags:-Llibs -l:android_main.a -landroid -llog -lEGL -lGLESv3"
	]
	if not args.debug:
		odin_cmd.extend(["-no-bounds-check", "-o:speed"])

	execute(odin_cmd, env=build_env)
	
	if not os.path.exists(final_lib_name):
		print(f"Error: Expected output file '{final_lib_name}' not found after compilation.")
		exit(1)

	shutil.move(final_lib_name, os.path.join(jni_libs_dir, final_lib_name))
	
	os.chdir(owd)
	
	print("Copying assets...")
	shutil.copytree("assets", assets_dir, dirs_exist_ok=True)

	print("Generating Android project files...")
	
	# Create local.properties file with SDK path
	sdk_path = find_android_sdk()
	if sdk_path:
		local_properties_path = os.path.join(out_dir, "local.properties")
		with open(local_properties_path, 'w') as f:
			# Convert Windows path to Unix-style for Gradle
			sdk_path_unix = sdk_path.replace('\\', '/')
			f.write(f"sdk.dir={sdk_path_unix}\n")
		print(f"Created local.properties with SDK path: {sdk_path}")
	else:
		print("Warning: Could not find Android SDK path")
	
	with open(os.path.join(out_dir, "settings.gradle"), "w") as f:
		f.write("include ':app'\n")
		
	project_gradle = """
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:8.1.4'
    }
}
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
task clean(type: Delete) {
    delete rootProject.buildDir
}
"""
	with open(os.path.join(out_dir, "build.gradle"), "w") as f:
		f.write(project_gradle)

	app_gradle = f"""
apply plugin: 'com.android.application'
android {{
    namespace '{package_name}'
    compileSdkVersion 33
    defaultConfig {{
        applicationId "{package_name}"
        minSdkVersion 26
        targetSdkVersion 33
        versionCode 1
        versionName "1.0"
    }}
    buildTypes {{
        release {{
            minifyEnabled false
        }}
        debug {{
            minifyEnabled false
        }}
    }}
    sourceSets {{
        main {{
            jniLibs.srcDirs = ['src/main/jniLibs']
            assets.srcDirs = ['src/main/assets']
        }}
    }}
}}
"""
	with open(os.path.join(app_dir, "build.gradle"), "w") as f:
		f.write(app_gradle)

	manifest_content = f'''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="{package_name}">
    
    <uses-permission android:name="android.permission.INTERNET" />
    
    <application
        android:allowBackup="true"
        android:label="{app_name}"
        android:theme="@android:style/Theme.NoTitleBar.Fullscreen">
        
        <activity android:name="android.app.NativeActivity"
            android:configChanges="orientation|keyboardHidden"
            android:exported="true">
            
            <meta-data android:name="android.app.lib_name"
                android:value="game" />
                
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>'''
	
	with open(os.path.join(main_dir, "AndroidManifest.xml"), "w") as f:
		f.write(manifest_content)
	
	gradlew_path = os.path.join(out_dir, "gradlew.bat" if IS_WINDOWS else "gradlew")
	if not os.path.exists(gradlew_path):
		print("Gradle wrapper not found, downloading...")
		gradle_version = "8.5"  # Updated to support Java 21
		wrapper_dir = os.path.join(out_dir, "gradle", "wrapper")
		make_dirs(wrapper_dir)
		
		# For newer Gradle versions, use the main branch
		download_file("https://raw.githubusercontent.com/gradle/gradle/master/gradlew", os.path.join(out_dir, "gradlew"))
		download_file("https://raw.githubusercontent.com/gradle/gradle/master/gradlew.bat", os.path.join(out_dir, "gradlew.bat"))
		download_file("https://github.com/gradle/gradle/raw/master/gradle/wrapper/gradle-wrapper.jar", os.path.join(wrapper_dir, "gradle-wrapper.jar"))
		
		wrapper_props = f"""
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https://services.gradle.org/distributions/gradle-{gradle_version}-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
"""
		with open(os.path.join(wrapper_dir, "gradle-wrapper.properties"), "w") as f:
			f.write(wrapper_props.strip())

		if not IS_WINDOWS:
			make_executable(gradlew_path)
			
	print("Building APK with Gradle...")
	build_type = "Debug"

	# Get Android SDK path and create local.properties
	android_sdk_path = get_android_sdk_path()
	if android_sdk_path:
		local_properties_content = f"sdk.dir={android_sdk_path.replace(os.sep, '/')}\n"
		with open(os.path.join(out_dir, "local.properties"), "w") as f:
			f.write(local_properties_content)
		print(f"Created local.properties with SDK path: {android_sdk_path}")
		build_env["ANDROID_HOME"] = android_sdk_path
	
	# Try to find Java 21
	java_paths = [
		r"C:\Program Files\Eclipse Adoptium\jdk-21.0.7.6-hotspot",
		r"C:\Program Files\Eclipse Adoptium\jdk-21.0.7.10-hotspot",
		r"C:\Program Files\Java\jdk-21",
		r"C:\Program Files\Temurin-21",
		r"C:\Program Files\Microsoft\jdk-21",
		os.path.expanduser(r"~\scoop\apps\temurin21-jdk\current"),
		os.path.expanduser(r"~\.jdks\temurin-21"),
	]
	
	java_home = None
	for path in java_paths:
		if os.path.exists(path):
			java_home = path
			break
	
	if java_home:
		print(f"Using Java from: {java_home}")
		build_env["JAVA_HOME"] = java_home
	
	os.chdir(out_dir)
	
	cmd = f".{os.sep}{os.path.basename(gradlew_path)} assemble{build_type}"
	execute(cmd, env=build_env)

	os.chdir(owd)
	
	apk_paths = [
		os.path.join(app_dir, "build", "outputs", "apk", "debug", "app-debug.apk"),
		os.path.join(app_dir, "build", "outputs", "apk", "release", "app-release-unsigned.apk"),
		os.path.join(app_dir, "build", "outputs", "apk", "release", "app-release.apk"),
	]
	
	apk_path = None
	for path in apk_paths:
		if os.path.exists(path):
			apk_path = path
			print(f"Found APK at: {path}")
			break
	
	if not apk_path:
		print("Error: APK not found at expected locations")
		for path in apk_paths:
			print(f"  - {path}")
		return None
	
	final_apk_path = os.path.join(out_dir, f"{app_name}.apk")
	shutil.move(apk_path, final_apk_path)
	
	print(f"Successfully built APK: {final_apk_path}")
	print("\nTo install the APK on a connected device:")
	print(f"  adb install {final_apk_path}")
	print("\nNote: Debug APKs are automatically signed and can be installed directly.")
	print("For release builds, you would need to sign the APK with your own keystore.")

	unpatch_sokol()

	return final_apk_path

def patch_sokol_for_android():
	"""Temporarily patch Sokol bindings to add Android support"""
	print("Patching Sokol bindings for Android...")
	
	# Note: sokol_app needs special handling for Android
	sokol_modules = [
		("app/app.odin", "sokol_app_clib", []),  # Empty libs for Android as we provide our own entry point
		("gfx/gfx.odin", "sokol_gfx_clib", ["system:log", "system:android", "system:EGL", "system:GLESv3"]),
		("gl/gl.odin", "sokol_gl_clib", ["system:log", "system:android", "system:EGL", "system:GLESv3"]),
		("glue/glue.odin", "sokol_glue_clib", ["system:log", "system:android"]),
		("log/log.odin", "sokol_log_clib", ["system:log", "system:android"]),
		("shape/shape.odin", "sokol_shape_clib", ["system:log", "system:android", "system:EGL", "system:GLESv3"]),
		("audio/audio.odin", "sokol_audio_clib", ["system:log", "system:android"]),
		("debugtext/debugtext.odin", "sokol_debugtext_clib", ["system:log", "system:android", "system:EGL", "system:GLESv3"]),
		("time/time.odin", "sokol_time_clib", ["system:log", "system:android"]),
	]
	
	for module_path, lib_name, android_libs in sokol_modules:
		full_path = os.path.join(SOKOL_PATH, module_path)
		if not os.path.exists(full_path):
			print(f"Warning: {full_path} not found, skipping...")
			continue
			
		with open(full_path, 'r', encoding='utf-8') as f:
			content = f.read()

		backup_path = full_path + ".android_backup"
		if not os.path.exists(backup_path):
			with open(backup_path, 'w', encoding='utf-8') as f:
				f.write(content)

		if "ODIN_PLATFORM_SUBTARGET == .Android" in content:
			print(f"Skipping already patched file: {module_path}")
			continue
		
		linux_block_start_str = "when ODIN_OS == .Linux {"
		
		if linux_block_start_str in content:
			
			android_libs_str_debug = f'\t\t\t"{lib_name.removesuffix("_clib")}_android_arm64_gles3_debug.a",\n'
			for lib in android_libs:
				android_libs_str_debug += f'\t\t\t"{lib}",\n'

			android_libs_str_release = f'\t\t\t"{lib_name.removesuffix("_clib")}_android_arm64_gles3_release.a",\n'
			for lib in android_libs:
				android_libs_str_release += f'\t\t\t"{lib}",\n'
			
			android_block = f'''when ODIN_PLATFORM_SUBTARGET == .Android {{
		when ODIN_DEBUG {{
			foreign import {lib_name} {{
				{android_libs_str_debug}
			}}
		}} else {{
			foreign import {lib_name} {{
				{android_libs_str_release}
			}}
		}}
	}} else {linux_block_start_str}'''

			new_content = content.replace(linux_block_start_str, android_block, 1)
			
			if new_content != content:
				with open(full_path, 'w', encoding='utf-8') as f:
					f.write(new_content)
				print(f"Patched {module_path} for Android.")
		else:
			print(f"Warning: Could not find '{linux_block_start_str}' block in {module_path}, skipping patch.")

def unpatch_sokol():
	"""Remove Android patches from Sokol bindings"""
	print("Removing Android patches from Sokol bindings...")
	
	# Just restore from backup
	for root, _, files in os.walk(SOKOL_PATH):
		for file in files:
			if file.endswith(".android_backup"):
				backup_path = os.path.join(root, file)
				original_path = backup_path.removesuffix(".android_backup")
				
				# Restore from backup
				shutil.move(backup_path, original_path)
				print(f"Restored {original_path}")

main()