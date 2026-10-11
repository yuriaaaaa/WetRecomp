# WetRecomp


> **Android fork / AI-assisted development**  
> This fork is intended to support development and experimentation toward running WET on Android. AI tools are used as development assistants for code analysis, implementation, debugging, and build troubleshooting, with changes reviewed and tested as practical. Android support and build status depend on the current branch and should not be assumed from the upstream platform description alone.

<div align="center">
  <img src="assets/icon.png" alt="WetRecomp" width="480">
</div>

A static recompilation of [**WET**](https://en.wikipedia.org/wiki/Wet_(video_game)) (2009, Xbox 360, Title ID `425307DB`) to native Windows/Linux x86-64, built on the [ReXGlue SDK](https://github.com/rexglue/rexglue-sdk).

## Status

Fully playable: video, audio, gameplay, achievements, and progression all work.

## Requirements

- CMake 3.25+, Ninja, Clang/LLVM (clang-cl works too)
- [extract-xiso](https://github.com/XboxDev/extract-xiso/releases) and your own legally-owned copy of WET:
  Title ID `584109C2` (XA-2498), Media ID `3077A693`, Module hash `9A084828F85F951B`

## Game data

Extract the Xbox 360 ISO with `extract-xiso.exe -x WET.iso`, then copy the contents into `assets/` (gitignored):

```
assets/
  default.xex
  nxeart
  lu0/  lu1/
  media/  movies0/  movies1/
  streams0/  streams1/
```

## Build

```bash
git clone --recurse-submodules <repo-url>
```

The ReXGlue SDK is built from the `thirdparty/rexglue-sdk` submodule; no prebuilt SDK is needed.

```powershell
cmake --preset win-amd64-relwithdebinfo
cmake --build out\build\win-amd64-relwithdebinfo
```

```bash
cmake --preset linux-amd64-relwithdebinfo
cmake --build out/build/linux-amd64-relwithdebinfo
```

## Run

```powershell
cd out\build\win-amd64-relwithdebinfo
.\wetrecomp.exe
```

Logs land in `out\build\<preset>\logs\*.log`.

## Configuration

`settings/hardware.toml` (rendering/perf, including `wet_gpu_wait_mode` for GPU-wait CPU usage) and `settings/mapping.toml` (input) load automatically. CLI flags and `REX_*` env vars override them. See [`settings/README.md`](settings/README.md) for the reference.

## Credits

- [ReXGlue SDK](https://github.com/rexglue/rexglue-sdk)
- [extract-xiso](https://github.com/XboxDev/extract-xiso)
- [xenia](https://github.com/xenia-project/xenia) / [xenia-canary](https://github.com/xenia-canary/xenia-canary)

### Android device compatibility

- **Reference test device:** Samsung Galaxy S25 with Snapdragon 8 Elite for Galaxy (Adreno 830 GPU, 12 GB RAM).
- **Test scope:** This identifies the current reference device only; it is not a minimum-requirements claim and does not imply that every feature or game has been fully validated on this device.
- **Other devices:** Compatibility and performance on other Android devices, including lower-end hardware, have not been established unless explicitly documented by a test result. Performance may vary with the GPU, graphics drivers, available memory, thermal behaviour, and game/runtime requirements.
- **No blanket exclusion:** Lower-end devices are not declared incompatible; they require testing before support can be claimed.

### Android port notes

What this fork changes for Android, and what was reverse-engineered along the way, is documented in [docs/ANDROID_PORT.md](docs/ANDROID_PORT.md).

The Android source is in this repository; [android/README.md](android/README.md) explains how to build the APK from your own legally obtained copy of the game. The repository contains no game files and no code recompiled from the game.
