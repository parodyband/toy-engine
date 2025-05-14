# Build System

This project uses a custom build system based on Odin. The `build_game.odin` script handles both desktop and web builds with a simple command-line interface.

## Basic Usage

### Desktop Build (Default)
```
.\build_game
```

### Web Build
```
.\build_game --web
```

### Web Build with Automatic Server and Browser
```
.\build_game --web --serve
```

## Command Line Options

| Option | Description |
| ------ | ----------- |
| `--web` | Build for web instead of desktop |
| `--serve` | Start a web server after web build completes |
| `--port=<num>` | Specify port for web server (default: 8000) |
| `--debug=<bool>` | Build with debug information (true/false) |
| `--opt=<level>` | Optimization level (none, speed, size) |
| `--out=<dir>` | Override output directory |
| `--emsdk=<dir>` | Path to Emscripten SDK directory |

## Examples

### Desktop Build with Size Optimization
```
.\build_game.exe --debug=false --opt=size
```

### Web Build with Custom Output Directory
```
.\build_game.exe --web --out=custom_build
```

### Web Build with Server on Port 9000
```
.\build_game.exe --web --serve --port=9000
```

### Web Build with Custom Emscripten SDK
```
.\build_game.exe --web --emsdk=D:\emscripten
```

## Build Outputs

### Desktop Build
- Outputs to `build/desktop` by default
- Executable, debug info (if enabled), and assets folder

### Web Build
- Outputs to `build/web` by default
- HTML, JavaScript, WebAssembly files, and preloaded assets

## Requirements

- [Odin](https://odin-lang.org/) compiler in PATH
- For web builds: [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html)
- Python 3 (for web server functionality)

## Customization

You can customize default settings by modifying the `SETTINGS` variable in `build_game.odin`:

```odin
SETTINGS := CONFIG{
    source_dir        = "source",
    assets_dir        = "assets",
    output_dir        = "", // Set based on build type
    executable_name   = "ToyGame",
    // ...and more settings
}
``` 