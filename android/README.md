# WET for Android: building

This folder holds the Android (arm64-v8a) port of WetRecomp: the launcher app, the Android
CMake project and JNI glue, the port's overlays on the ReXGlue SDK, Vortek, and the build scripts.
WetRecomp's own Android changes are in `../src/utils.h` and `../src/wetrecomp_app.h`
(`__ANDROID__` branches). What the port does and what was reverse-engineered is described in
[docs/ANDROID_PORT.md](../docs/ANDROID_PORT.md).

## You need your own copy of the game

**This repository contains no game files, no code recompiled from the game and no prebuilt APK.**
To build and play, you need your own legally obtained copy of WET for Xbox 360 (Title ID
`425307DB`), as a disc image (ISO) you made yourself or as an extracted game folder.

- The build reads only `default.xex` from your copy and recompiles it on your computer
  (`rexglue codegen`). The output (`../generated/default`) is git-ignored and stays on your machine.
  The tested build is the USA/Europe disc (Media ID `666E3BB8`); the script warns if your
  `default.xex` differs.
- On the phone, the launcher plays the game from your own ISO or extracted folder.
- Do not share the APK you build: it contains code recompiled from your copy of the game.

## Requirements

- Linux x86_64 with clang 19 or newer (set `CC`/`CXX`), CMake, Ninja and Git
- Android SDK with platform 35 and build-tools 35, and **NDK 27.2.12479018**
- JDK 17

## Build

```sh
git clone https://github.com/yuriaaaaa/WetRecomp
cd WetRecomp
export ANDROID_HOME=$HOME/Android/Sdk
export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/27.2.12479018
export CC=clang-19 CXX=clang++-19

android/build.sh --xex /path/to/your/default.xex
```

The APK is written to `android/build/out/WET-android-arm64.apk`. If your game is an ISO, extract
`default.xex` from it first with an Xbox 360 ISO extraction tool. The recompiled code is large, so
the native build takes a long time.

`android/build.sh --skip-game` runs only what doesn't need the game: the launcher unit tests, the
Android builds of AdrenoTools, Vortek and the SDK libraries with the port's overlays, and a
launcher-only APK, which has no game library and can't start the game. It is a check that the
sources build.

The steps can also be run one by one:

```sh
git submodule update --init --depth 1 --recursive android/rexglue-sdk android/native/thirdparty/libadrenotools
bash android/scripts/apply_overlays.sh          # port overlays onto android/rexglue-sdk
WET_XEX=/path/to/default.xex bash android/scripts/build_host_codegen.sh
bash android/scripts/build_android_native.sh    # librestuff.so, Xenos plugin, AdrenoTools, Vortek
(cd android && ./gradlew :app:assembleRelease)
```

`.github/workflows/android.yml` runs the same build on GitHub Actions (manual trigger). Without
`android/game/default.xex` it only runs the checks that don't need the game.

### Signing

The release APK is signed with the debug key unless you provide your own:

```sh
export WET_KEYSTORE=/path/to/your.keystore   # or put it at android/keystore/release.keystore
export WET_STORE_PASSWORD=... WET_KEY_ALIAS=... WET_KEY_PASSWORD=...
```

An APK signed with a different key can't be installed over an earlier build; uninstall the old one
first.

## On the phone

Install the APK, open **WET**, tap **Select ISO** and pick your own WET disc image or extracted
folder (it is read in place; nothing is copied). Settings include the graphics driver (system or an
imported Turnip driver), touch controls and the 60 FPS option.

## Layout

```
android/
  app/            Kotlin launcher (internal package com.deivid22srk.restuff, kept because the JNI
                  symbols bind to it; installed app id com.rexglue.wet) and SDL3's Java layer
  native/         Android CMake project, jni/android_main.cpp
    overlay/rexglue-sdk/   the port's changes to the SDK, copied over android/rexglue-sdk by
                           scripts/apply_overlays.sh (Android surface, fibers, file system, input,
                           Vulkan fixes for Adreno, GPU plugin loading, custom drivers)
    thirdparty/vortek, vortekrenderer   Vortek (brunodev85, LGPL-2.1), with local changes
    thirdparty/libadrenotools           submodule, bylaws/libadrenotools @ 8fae8ce
  rexglue-sdk/    submodule, rexglue/rexglue-sdk @ bd833a2 (WetRecomp's pin), a separate checkout
                  so the overlays don't touch the desktop build's thirdparty/rexglue-sdk
  scripts/        apply_overlays.sh, build_host_codegen.sh, build_android_native.sh
  game/           put your default.xex here if you don't use --xex (git-ignored)
  build.sh        runs everything
```

## Credits

- WetRecomp: nikolaygorb
- ReXGlue SDK: Tom Clay and contributors (BSD-3-Clause, Xenia-derived)
- Android wrapper, SDK overlays and the AdrenoTools/Vortek integration this port starts from:
  Hailgames, [naughtybear-restuff-android](https://github.com/deivid22srk/naughtybear-restuff-android)
- Vortek: brunodev85 (LGPL-2.1); libadrenotools: bylaws (BSD-2-Clause)
