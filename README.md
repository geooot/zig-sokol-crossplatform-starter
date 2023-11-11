# zig-sokol-crossplatform-starter
A template for an app that runs on iOS, Android, PC and Mac. Built using [sokol](https://github.com/floooh/sokol), and [zig](https://ziglang.org).

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
