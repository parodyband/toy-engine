## Building the Project (Quick Start)

This project uses a simple Odin build script located at `build_system/build_game.odin`.

**Step 1: Compile the build script**
From the root directory, run:

```
odin build build_system/build_game.odin -file
```

**Step 2: Run the build script**

For desktop builds (default):
```
.\build_game
```

For web builds:
```
.\build_game --web
```

For web builds with automatic server and browser:
```
.\build_game --web --serve --port=8080
```

## Requirements

- [Odin](https://odin-lang.org/) compiler in PATH
- For web builds: [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html)
- Python 3 (for web server functionality)

For detailed build options and customization, see [BUILD.md](build_system/BUILD.md).


> [!WARNING]
> If the desktop build says that there are libraries missing, then you need to go into `source/sokol` and run one of the `build_clibs...` build scripts.