
<div align="center">
<h1>webgpu-wasm-zig</h1>

<p>A minimal WebGPU example written in Zig, compiled to WebAssembly (wasm).</p>

<img src="screen.png"/>
  
![👁️](https://views.whatilearened.today/views/github/seyhajin/webgpu-wasm-zig.svg)

</div>

## Getting started

### Clone

```bash
git clone https://github.com/seyhajin/webgpu-wasm-zig.git
```

Alternatively, download [zip](https://github.com/seyhajin/webgpu-wasm-zig/archive/refs/heads/master.zip) from Github repository and extract wherever you want.

### Build

Build the example with `zig build` command, which will generate 3 new files (`.html`, `.js`, `.wasm`).

#### Command
```
zig build --sysroot [path/to/emsdk]/upstream/emscripten/cache/sysroot
```

Example with Emscripten installed with Homebrew (`brew install emscripten`, v3.1.51) on macOS :
```
zig build --sysroot /usr/local/Cellar/emscripten/3.1.51/libexec/cache/sysroot
```

> [!NOTE] 
> `build.zig` is preconfigured to build to `wasm32-emscripten` target only. 

> [!CAUTION] 
> Must provide Emscripten sysroot via `--sysroot` argument. 

### Run

Launch a web server to run example before open it to WebGPU compatible web browser (Chrome Canary, Brave Nightly, etc.).

e.g. : launch `python3 -m http.server` and open web browser to `localhost:8000`.

> [!TIP]
> Use [Live Server](https://marketplace.visualstudio.com/items?itemName=ritwickdey.LiveServer) extension in Visual Studio Code to open the HTML file. This extension will update automatically page in real-time when you rebuild the example.

## Prerequisites

* [zig](https://www.zig.org/download), works with Zig 0.12+dev version
* [emscripten](https://emscripten.org), version 3.1+
* git (optional)
* python3 (optional)

