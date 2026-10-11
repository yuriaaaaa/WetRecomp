# Baton: WET Android port, state at 1.0.16
From: claude · Date: 2026-10-11 · Repo commit: afd796c

**TL;DR:** The Android port plays on a Galaxy S25 ("nearly perfect" at 1.0.14, less stutter in 1.0.16). Nothing is broken right now. Next for ChatGPT: research whether newer ReXGlue SDK versions or Xenia forks relax the `vertexPipelineStoresAndAtomics` requirement, so Mali phones could run it.

## Goal
A playable arm64 Android build of WET (Title ID `425307DB`) from this fork, built by players from their own `default.xex`. Source-only releases.

## State of play (verified)
- Android source is on `main` under `android/` (launcher, SDK overlays, build scripts). Build: `android/build.sh --xex /path/to/default.xex`; `android/build.sh --skip-game` passed on 2026-10-11 from a fresh clone.
- Pinned toolchain: rexglue-sdk `bd833a2` (v0.10.0 + Android overlays), libadrenotools `8fae8ce`, NDK 27.2, AGP 8.7.3, Gradle 8.14.3.
- Latest device-tested build: 1.0.15 on the S25 (Adreno 830), "getting better, small stuttering". 1.0.14: saving works, controller fixed, "nearly perfect".
- 1.0.16 changed the write-watch fault path so it no longer reads `/proc/self/maps` under the global lock (the main stutter cause). See `docs/ANDROID_PORT.md`.
- Full history of every build and fix: `docs/ANDROID_PORT.md`.

## Assumed / unverified
- That 1.0.16 removes most of the remaining stutter: it was built and checked (symbols, signing, unit tests) but no device result has come back.
- Intro movies after the texture fix: not confirmed.

## Findings and dead ends
- The black 3D scene (1.0.1–1.0.6) was the SPIR-V translator reading the texture exponent bias from the wrong fetch-constant word. Fixed in 1.0.7; don't revisit.
- Vortek (non-Adreno wrapper) fails with "Failed to get all Vulkan instance function pointers". Low priority.
- Quitting the game can SIGABRT in `KernelState::TerminateTitle`. Harmless.
- Mali-G57: the SDK always requires `vertexPipelineStoresAndAtomics`; the cvar that used to relax it is deprecated and ignored.

## Next task for ChatGPT
Research only, no code:
1. In upstream ReXGlue SDK (commits after `bd833a2`) and in Xenia / Xenia Canary / xenia-edge, is there a path that runs without `vertexPipelineStoresAndAtomics` (for example memexport emulated in compute, or a fallback)? Give file paths and commit links.
2. List ReXGlue SDK changes after `bd833a2` that mention Android, Adreno, Vulkan or memory/MMIO performance, with commit links.
3. Drop a baton `.baton/YYYY-MM-DD-chatgpt-mali-research.md` with findings, separating what you read in source from what you infer.

## Open questions for David
- Did 1.0.16 feel smoother than 1.0.15 on the S25?
