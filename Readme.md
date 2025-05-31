## Building the Project (Quick Start)

This project uses a Python build script located at `build.py`.

### Basic Build Commands

**Development build with hot reload:**
```
python build.py -hot-reload
```

**Release build:**
```
python build.py -release
```

**Web build:**
```
python build.py -web
```

**Build and run immediately:**
```
python build.py -release -run
python build.py -web -run -port=8080
```

### Build Options

- `-hot-reload` - Build hot reload game DLL. Supports live code reloading while the game is running.
- `-release` - Build optimized release executable. Creates a clean build in `build/release`.
- `-web` - Build for web using Emscripten. Outputs to `build/web`.
- `-capture` - Build and run with RenderDoc capture (Windows only).
- `-run` - Run the executable after building. For web builds, starts a local server.
- `-debug` - Create debuggable binaries (works with all build modes).
- `-shaders` - Compile shaders only (useful for quick shader iteration).
- `-no-shader-compile` - Skip shader compilation.
- `-gl` - Force OpenGL backend (useful for older hardware).
- `-port=<number>` - Port for web server when using `-run` with web builds (default: 8000).

### First Time Setup

The build script will automatically download Sokol bindings and shader compiler on first run. You can also manually update them:

```
python build.py -update-sokol
python build.py -compile-sokol
```

## Requirements

- [Python 3](https://www.python.org/)
- [Odin](https://odin-lang.org/) compiler in PATH
- For web builds: [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html)
  - Either in PATH or use `-emsdk-path=<path>` flag
- For Windows Sokol compilation: Visual Studio (for cl.exe)
- Optional: [RenderDoc](https://renderdoc.org/) for graphics debugging

## Platform Notes

### Windows
- Sokol compilation requires running from a Visual Studio command prompt or having cl.exe in PATH

### macOS
- Release builds create a `.app` bundle
- Use `-app-name=<name>` to customize the app bundle name (default: ToyGame)
- Older Macs may need `-gl` flag if they don't support Metal

### Linux
- The build script will automatically set execute permissions on built binaries

## Troubleshooting

If you get library errors on desktop builds, you may need to compile the Sokol libraries:
```
python build.py -compile-sokol
```