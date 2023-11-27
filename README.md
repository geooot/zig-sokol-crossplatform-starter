# zig-sokol-crossplatform-starter
A template for an app that runs on iOS, Android, PC and Mac. Built using [sokol](https://github.com/floooh/sokol), and [zig](https://ziglang.org).

https://github.com/geooot/zig-sokol-crossplatform-starter/assets/7832610/a364499c-ed60-4376-89fa-d8c9171fcaad

## Clone
```
git clone --recurse-submodules https://github.com/geooot/zig-sokol-crossplatform-starter.git
```

## Dependencies
For iOS
- xcode
- `xcodegen`, which can be installed with `brew install xcodegen`

## Usage
```
$ zig build run      # builds and runs executable on your computer

$ zig build          # builds everything
$ zig build ios      # builds iOS project
$ zig build default  # builds a standard exe build based on your target
```
