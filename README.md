# zig-sokol-crossplatform-starter

A template for an app that runs on iOS, Android, PC and Mac. Built using [the Zig programming language](https://ziglang.org), and using the [`floooh/sokol`](https://github.com/floooh/sokol) graphics/app library.
Also, taken inspiration from [`kubkon/zig-ios-example`](https://github.com/kubkon/zig-ios-example), [`MasterQ32/ZigAndroidTemplate`](https://github.com/MasterQ32/ZigAndroidTemplate), and [`cnlohr/rawdrawandroid`](https://github.com/cnlohr/rawdrawandroid)

<video src="https://github.com/geooot/zig-sokol-crossplatform-starter/assets/7832610/3d7cbba5-28a3-4ad1-bc0e-4f22af35d73c" muted autoplay loop style="width: 100%"></video>

## Clone

> [!IMPORTANT]  
> This projects uses submodules. Make sure to include them.

```
git clone --recurse-submodules https://github.com/geooot/zig-sokol-crossplatform-starter.git
```

## Required Dependencies

You will need the `0.12` release of Zig, you can find it [here](https://ziglang.org/download). 

For iOS
- xcode
- Edit `build.zig` with `APP_NAME` and `BUNDLE_PREFIX` changed as necessary.

For Android
- [Android SDK](https://developer.android.com/studio) install with `ANDROID_HOME` environment variable set. 
- Java JDK, and `keytool` (should be included in JDK install). `$JAVA_HOME` should be set to the install location
- Edit `build.zig` with `ANDROID_` prefixed constants as necessary. You probably only need to change `*_VERSION` const's to match what you have installed in your android SDK (check `$ANDROID_HOME`).
- Edit `build.zig` with `APP_NAME` and `BUNDLE_PREFIX` changed as necessary.

For PC/Mac
- Nothing! Just `zig build run`.

## Build and Run

Make sure to perform the edits and get the dependencies described in ["Required Dependencies"](#Required-Dependencies) before continuing below.

```sh
$ zig build run      # builds and runs executable on your computer

$ zig build          # builds everything (iOS, android, your computer)

$ zig build ios      # generates iOS project (in zig-out/MyApp.xcodeproj).
                     # You have to open xcode and build from there

$ zig build android  # builds android apks (in zig-out/MyApp.apks).
                     # You have to use `bundletool install-apks --apks=MyApp.apks` to install it to a device.
                     # But you use the `.aab` file when submitting to Google Play.

$ zig build default  # builds a executable for your computer
```

## Quirks and Features

Features
- Ability to build for your PC, iOS, and Android
- Android App Bundle support.
- XCode project is an artifact. Configuration using YAML instead (thanks to `xcodegen`)
- Pretty easy to modify build system (thanks to Zig).
- Small binaries, fast loading times!

Quirks
- Not really easy to debug for android. Surprisingly the xcode debugger works pretty well.
- Still need XCode to finish the build for iOS. It's needed for code signing and final linking.

## Things that would be cool to add in the future

In no particular order
- [x] Move sokol-zig to be a zig dependency rather than a git submodule
- [x] Can we get rid of the dependency on `xcodegen` and `bundletool`? I think we can at least use zig package manager to fetch those dependencies on build. We need zip support (xcodegen releases itself as a zip file rather than a tarball) and single file download support (bundletool packages itself as a single `.jar`) to make that possible. 
   - Even crazier idea: reimplement `xcodegen` and `bundletool` as zig libraries.
- [ ] In my sleep I still think about `kubkon/zig-ios-example` since it doesn't require generating a xcode project at all. I think in reality, people might need **some** xcode project generation support, but like...
- [x] Github Action CI/CD workflows.
- [ ] Add minimal WASM/WASI builds (lets move past emscripten).

## License

This is Public Domain software with the UNLICENSE license. All code except for the following exceptions are under the UNLICENSE license.
- `build/auto-detect.zig` falls under the MIT License [[[See here]]](https://github.com/MasterQ32/ZigAndroidTemplate/blob/master/LICENCE).
- `sokol-zig` (and sokol in general) fall under the Zlib license [[[See here]]](https://github.com/floooh/sokol/blob/master/LICENSE).
