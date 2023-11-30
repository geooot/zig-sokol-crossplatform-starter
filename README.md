# zig-sokol-crossplatform-starter
A template for an app that runs on iOS, Android, PC and Mac. Built using [zig](https://ziglang.org), and [sokol](https://github.com/floooh/sokol).
Also, inspiration from [kubkon/zig-ios-example](https://github.com/kubkon/zig-ios-example), [MasterQ32/ZigAndroidTemplate](https://github.com/MasterQ32/ZigAndroidTemplate), and [cnlohr/rawdrawndroid](https://github.com/cnlohr/rawdrawandroid)

<video src="https://github.com/geooot/zig-sokol-crossplatform-starter/assets/7832610/a364499c-ed60-4376-89fa-d8c9171fcaad" muted autoplay loop></video>

## Clone
> [!IMPORTANT]  
> This projects uses submodules. Make sure to include them.

```
git clone --recurse-submodules https://github.com/geooot/zig-sokol-crossplatform-starter.git
```

## Required Dependencies
For iOS
- xcode
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen), which can be installed with `brew install xcodegen`
- Edit `build.zig` with `APP_NAME` and `BUNDLE_PREFIX` changed as necessary.

For Android
- [Android SDK](https://developer.android.com/studio) install with `ANDROID_HOME` environment variable set. 
- Java JDK, and `keytool` (should be included in JDK install). `$JAVA_HOME` should be set to the install location
- [`bundletool`](https://github.com/google/bundletool), which can be installed with `brew install bundletool`.
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
                     # But you use the `.apks` file when submitting to Google Play.

$ zig build default  # builds a executable for your computer
```
