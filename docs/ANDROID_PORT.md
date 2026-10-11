# WET for Android: port notes

An Android (arm64-v8a) port of [WetRecomp](https://github.com/nikolaygorb/WetRecomp), running on the ReXGlue SDK with Vulkan. Latest build: **1.0.16** (package `com.rexglue.wet`).

## What was implemented

- **Android launcher and wrapper** based on the Naughty Bear Android wrapper, with SDL3's Java layer re-synced to the SDK's SDL 3.4.14 (the cause of the 1.0.0 crash on Start Game).
- **Vulkan fixes for Adreno:**
  - A bug in the SDK's SPIR-V shader translator read the texture exponent bias (`exp_adjust`) from fetch-constant word 4 instead of word 3, scaling almost every texture by 1/256. This was the cause of the black 3D scene.
  - Depth restore fix for D24FS8 with host render targets, and a workaround for Qualcomm's float-controls shader bug (`wet_param_gen_variant`, auto-detected per driver and cached).
- **Performance:** write-watch faults no longer re-read `/proc/self/maps` under the global lock (the main cause of stutter in 1.0.15), and `AllocFixed` commits no longer scan the memory map.
- **Graphics drivers:** Turnip / custom driver import through libadrenotools.
- **Input:** touch controls, controller ordering fixes so saving works with any pad, and merged controllers for player 1.
- **Saves:** working save device selection.
- Diagnostics: GPU state dumps, frame traces, shader dumps and per-frame lock / upload timings in the logs.

## Status of the source code

The Android port was developed and built on a temporary Linux build machine. The source changes themselves (the Android launcher app, the native overlays on the SDK, and the build scripts) were not committed anywhere before that machine was recycled, so **they are not in this repository yet**. This document records what was implemented and what was reverse-engineered, in enough detail to rebuild it. Code will be added here if the sources are recovered or rewritten.

No game files and no code recompiled from the game are included in this repository. Builds must be made from your own legally obtained copy of the game.

Reference test device: Samsung Galaxy S25 (Snapdragon 8 Elite, Adreno 830). Results on other devices have not been tested.

---

## Build log: WET Android: local build notes (7–8 Oct 2026)

First successful build of the signed APK from wet-android `60e514c` (WetRecomp `d921bad`, rexglue-sdk `bd833a2`, libadrenotools `8fae8ce`), on a Linux build machine (2 vCPU, 8 GB RAM).

## Current build: 1.0.16
- `WET-arm64-release.apk`: versionCode 17 / versionName 1.0.16, package `com.rexglue.wet`, arm64-v8a only
- APK SHA-256 `ebc153f8ff0d9613d0f12a73462c90987ed489fa52ab09b5ddd20ea2937a4847`; zip SHA-256 `ffcefba5d9b73f1080fb52227066188c1db06f3a9dfa860b9778da8f40000a21`
- Built with `RESTUFF_VERSION_CODE=17 RESTUFF_VERSION_NAME=1.0.16`
- Main change: write-watch faults no longer scan `/proc/self/maps` under the global lock (see "Findings from 1.0.15 and changes in 1.0.16").

Earlier builds:

| Version | APK SHA-256 | Result on the device |
|---|---|---|
| 1.0.0 (code 1) | `ea9cafa2…` | Crashed on Start Game |
| 1.0.1 (code 2) | `faf8b5f5…` | Boots; sound and controls work; 3D scene is black |
| 1.0.2 (code 3) | `a7c72f8f…` | Still black, with the stock driver and with Turnip; Vortek fails to start |
| 1.0.3 (code 4) | `d506a306…` | Still black; aiming reticle visible; draw statistics collected |
| 1.0.4 (code 5) | `90be5c21…` | Still black; more 2D UI visible (slide icons, kill points); GPU state dumps collected |
| 1.0.5 (code 6) | `a7255b6d…` | Still black with post-processing off; music works, less cutscene stutter; HUD, subtitles and mission prompts visible; frame traces collected |
| 1.0.6 (code 7) | `3a1bf7e3…` | Still black (diagnostic build); occasional white flashes in cutscenes; texture probe pinned the bug to shader-side sampling |
| 1.0.8 (code 9) | `f4e1ea37…` | Test switches. With `wet_vk_allow_reverse_z = false` the stock driver is still grey (no change). Traces located the grey pass. |
| 1.0.9 (code 10) | `f21e2cf2…` | Same two problems. Logs pinned both causes (see "Findings from 1.0.9"). Turnip felt laggy. |
| 1.0.15 (code 16) | `e0efe7f2…` | "Getting better, small stuttering"; reached the next checkpoint from a continued save. Heavier scene than the 1.0.14 run (median 1313 draws/frame, 5.9 swaps/s); lock wait 68 ms/frame for 681 locked requests, upload 6.6 ms, 95 CPU write faults per frame. |
| 1.0.14 (code 15) | `725c9441…` | **"Nearly perfect."** Saving works (device selector, 17 `save:` mounts), the headphone device is ignored, and the Xbox pad joined player 1 mid-session. Minor dips remain (median 8.5 swaps/s with 400+ draws; lock wait 18–39 ms, upload 6–26 ms, textures 6–24 ms per frame). |
| 1.0.13 (code 14) | `65c684e6…` | Gameplay better, dips with many enemies. **Saving stopped working.** That turned out to be controller ordering, not the build (see below). |
| 1.0.12 (code 13) | `e555d1fd…` | English launcher confirmed. With `clear_memory_page_state = false`: no glitches through the sword tutorial and the pole-swing area, about 20 fps; music stutters, and cutscene loads stutter. |
| 1.0.11 (code 12) | `5423cf81…` | **Stock driver: everything renders, no glitches, saving works.** Stutter and frame drops remain (5–10 fps in busy scenes). |
| 1.0.10 (code 11) | `35921878…` | **Stock driver: world renders and legs show.** The search locked variant 8 (no float controls) after 1, 2 and 4 failed, about 3.5 min in, and saved it. Turnip not tested on this build. Gameplay about 5–7 fps. |
| 1.0.7 (code 8) | `6ae617ff…` | **Turnip: the world, cutscenes, menus and title screen render**, but Rubi's legs are missing. Stock Qualcomm driver: menus and textured UI render, but the world is flat grey/brown. |

## Fix in 1.0.1: crash on Start Game
- **Symptom (Galaxy, 1.0.0):** the launcher shows "Ready · default.xex". Tapping **Start Game** closes the app within a second, with no dialog.
- **Cause:** the SDL Java layer in `app/src/main/java/org/libsdl/app` (inherited from the Naughty Bear wrapper) was stock SDL 3.5.0, but rexglue-sdk `bd833a2` ships native SDL **3.4.14**.
  - SDL's `JNI_OnLoad` calls `RegisterNatives`, which failed for two classes:
    - `SDLControllerManager`: `onNativePadDown` / `onNativePadUp` are `(III)Z` natively but `(II)Z` in Java; `nativeAddJoystick` has 4 booleans vs 2; `onNativeJoySensor` is missing from Java.
    - `HIDDeviceManager`: `HIDDeviceConnected` lacks the trailing `int reportID`.
  - The resulting `NoSuchMethodError` escapes `SDLActivity.loadLibraries()`, which catches only `UnsatisfiedLinkError` and `Exception`.
- **Fix:** copy all files from `rexglue-sdk/thirdparty/sdl3/android-project/app/src/main/java/org/libsdl/app/` over the app's copies. This adds `SDLSensorManager.java` and sets the version constants to 3.4.14.
  - The old files had no wrapper-specific changes, only version drift.
  - Native libraries are unchanged; only a Gradle rebuild is needed.
- **Rule for future SDK bumps:** whenever `rexglue-sdk/thirdparty/sdl3` changes, re-copy SDL's Java files from that same checkout.
- **Confirmed on the device:** 1.0.1 boots into the game.

## Fix in 1.0.7: 3D scene renders black (root cause found)
- **Root cause:** a bug in the SDK's SPIR-V shader translator (`src/graphics/pipeline/shader/spirv_translator_fetch.cpp`, texture fetch).
  - It applied the texture result exponent bias (`exp_adjust`) from **bits 13:18 of fetch-constant word 4**.
  - Those bits are part of the LOD bias (word 4 bits 12:21). `exp_adjust` lives in **word 3** bits 13:18, per `xe_gpu_texture_fetch_t` and the DXBC translator (`RequestTextureFetchConstantWord(tfetch_index, 3)`).
  - WET sets an LOD bias of -0.5 (`0x3F0`, fetch dword 4 = `0x003F0x03`) on almost every texture. Bits 13:18 of that are `0b111000` = -8, so every such texture's result was multiplied by 2^-8 (1/256).
  - Effects: the world comes out near-black, and alpha-blended textured UI (button-prompt icons, menu images) becomes invisible. Textures with an LOD bias of 0 were unaffected, which explains the occasional dim brown cutscene frame.
  - Windows desktop builds use D3D12/DXBC, which reads the right word; that is why WetRecomp is "fully playable" there. Any Vulkan user of this SDK pin hits the bug whenever a game uses a non-zero LOD bias.
- **Fix:** overlay `native/overlay/rexglue-sdk/src/graphics/pipeline/shader/spirv_translator_fetch.cpp` loads fetch-constant word 3 and extracts bits 13:18 from it. This is a one-place change, worth upstreaming to rexglue-sdk.
- **How it was found:**
  - 1.0.5 frame traces showed every textured draw resolving to black, while the untextured HUD and subtitle draws (flat vector shapes) were fine.
  - In 1.0.6, the texture probe showed, for world DXT1/DXT5 textures, menu DXT5 quads and resolve targets, that:
    - guest memory had real data
    - the GPU shared-memory copy matched it exactly (0 differing dwords)
    - the texture image's mip 0 read back correctly (endian-swapped as expected)
    - the image view was created and bound
  - The `WETDBG tex/60f` counters showed 0 creation failures and 0 load failures.
  - So the fault had to be after sampling. Comparing the SPIR-V and DXBC fetch translators then found the wrong word.
- **Side findings from 1.0.6:**
  - About 30 texture reloads per frame. This may be worth a look later for performance.
  - The PS constants of world shaders contain integer-looking garbage in some slots (c9–c15). This is probably unused registers, not a bug.
  - During the first ~3 minutes after boot, every trace showed a 3-plane YUV draw (ps `F62C0DC9C7803633`) whose Y plane is constant `0x10` and U/V constant `0x80`, i.e. a black video frame. If intro videos still show black after 1.0.7, look at the game's video decoder (CPU side), not the GPU.
- **Earlier investigation, for the record:**
  - Device: Adreno 830 (S25), page size 4096. Game data lives at `/storage/emulated/0/WET Android/game` (lu0, lu1, media, movies0/1, streams0/1, default.xex, nxeart). The only missing files are optional `*.en_US.lu` localisations and `default.xexp`.
  - Not the driver: Turnip (Mesa 26.3.0-devel) and the Qualcomm driver behave identically. Both report `textureCompressionBC`, so DXT textures are uploaded as native BC1/BC3.
  - Not async placeholders, the page-size offset, or post-processing.
  - The 1.0.4 state dumps showed sane 3D draws: plausible matrices, a full 1280×720 viewport, reversed-Z (`GEQUAL`, `RB_DEPTHCONTROL = 0x00100366`), colour RT 1× `k_8_8_8_8` at EDRAM base 782 / pitch 1360, depth D24FS8.
  - Ruled out by reading the code:
    - the Android Vulkan overlays
    - the ARM64 SIMD paths, the MMIO decoder and write-fault detection (ESR)
    - PowerPC barriers, `cntlzw`/`extsb`, and Android shared memory
    - `NtReadFile` invalidation
    - texture layout transitions, barrier helpers and register-write invalidation of constant buffers
- **Diagnostics available** (all in the Vulkan overlays; set through Engine options):
  - `wet_draw_stats` (default on): `WETDBG draws/60f` and `WETDBG tex/60f` (texture create/load counts and failures, descriptor views ok/null).
  - `wet_frame_trace_interval = N` (default 0 since 1.0.7; was 300): every N frames, logs every draw and resolve of one frame with a pixel summary of each resolve. Causes a short hitch.
  - `wet_tex_probe = N` (default 0 since 1.0.7; was 3): in traced frames, probes the textures of the first N textured colour draws (fetch dwords, binding state, guest memory vs GPU copy vs image read-back). `wet_tex_probe_readback` (init-only, default on) gives textures `TRANSFER_SRC` usage when the probe is enabled at boot.
- **Launcher-config differences from WetRecomp's desktop `hardware.toml`** (inherited from the Naughty Bear wrapper): `readback_resolve = "none"` (since 1.0.2), `native_2x_msaa = false`, `resolution_scale = 1`. `gpu_allow_invalid_fetch_constants = true` and `clear_memory_page_state = true` are the same as desktop. Post-processing still starts off (`wet_disable_depth_of_field`, `wet_disable_motion_blur`, `wet_disable_shaky_camera` = true); with the texture fix it should be safe to turn back on, which is the next test.
- **Earlier builds:**
  - **1.0.2:** `readback_resolve = "none"`, `vulkan_sparse_shared_memory = false`, the **Engine options (advanced)** box in Settings (`game/EngineOverrides.kt`, with a unit test), and a config copy next to each log.
  - **1.0.3:** the `WETDBG draws/60f:` statistics (cvar `wet_draw_stats`) and the async placeholder warning in the `pipeline_cache.cpp` overlay.
  - **1.0.4:** `-fno-strict-aliasing -ffp-model=strict -fno-char8_t` for `wetrecomp_recomp` and `restuff` in `native/CMakeLists.txt` (the SDK's directory-scoped flags never reached them), plus the `WETDBG state/viewport/vs consts/vfetch` dumps.
  - **1.0.5:** post-processing off by default, the frame trace, and the friend's `rexglue-unregistered-call.patch` as an overlay of `src/system/function_dispatcher.cpp`.
  - **1.0.6:** the texture probe and the texture counters (overlays `vulkan/texture_cache.cpp`, `vulkan/command_processor.cpp`, header `vulkan/wet_tex_probe.h`), and the trace line cap raised from 600 to 1400.

## Open issues after 1.0.7
- **Stock Qualcomm driver, flat grey world** (recording 23:40, log `restuff_20261007_233907`):
  - The world and cutscenes are one flat colour (light grey in cutscenes, dark brown in gameplay); menus, the HUD and button icons are correct.
  - Turnip renders the same scenes properly, so it is something only Qualcomm's compiler/driver does differently.
  - Evidence from the 1.0.5 traces:
    - Qualcomm: the gameplay depth resolve (T#22 `c0`) was only 16% non-zero, against 100% on Turnip.
    - Qualcomm: the cutscene trace T#20 had full depth but a near-uniform colour.
  - Candidates:
    - the reversed viewport depth range (`minDepth 0.5 > maxDepth 0`; D3D12 passes `allow_reverse_z = false`)
    - float-control execution modes
    - depth-prepass/colour-pass invariance (Qualcomm may ignore NoContraction/Invariant)
- **Turnip, Rubi's legs missing:**
  - Everything below her shorts is absent and the floor shows through, so the legs are not drawn at all; it is not a depth hole.
  - Possible causes: skinning (bone constants via dynamic addressing, or the blend-index vertex format), a kill/demote problem, or a skipped draw.
  - The extended trace line (prim, VS constant count and `/dyn`, kill, `sc_mode`) should identify her draws.
- **White full frames** around retry/restart: they come in pairs (about 0.1 s, then about 0.4 s, 1.3 s apart) on both drivers and line up with the film-leader countdown. Probably the game's own transition, not a bug.
- **Test switches in 1.0.8** (Engine options; most take effect on the next game start):
  - `wet_vk_allow_reverse_z` (default true): false flips Z in the VS and keeps `minDepth < maxDepth`, as the D3D12 path does.
  - `wet_vk_float_controls` (default true): false drops the SignedZeroInfNanPreserve/DenormFlushToZero/RoundingModeRTE execution modes.
  - `wet_skip_depth_prepass` (default false): drops depth-only draws (no PS, depth write on). Counted as `prepass=` in `WETDBG draws/60f`.
  - `wet_vk_demote` (default true): false uses OpKill instead of OpDemoteToHelperInvocation.
  - The first three and the trace extension were written in an interrupted branch of the session (around 23:53); `wet_vk_float_controls` was added afterwards. All live in the `vulkan/command_processor.cpp` and `vulkan/pipeline_cache.cpp` overlays.
- **Requested test plan:**
  1. stock driver, empty options
  2. stock driver with `wet_vk_allow_reverse_z = false`
  3. Turnip with Rubi on screen
  4. the remaining switches, one at a time

## Findings from 1.0.8 (logs `restuff_20261008_001030` stock, `_001332` stock with reverse-Z off, `_001519` Turnip with reverse-Z off)
- **Qualcomm grey world is one post-process pass, not the 3D scene.**
  - On the stock driver, the scene resolve (`c1`, RT0 → 0x079F8000) and the depth resolve are as varied and complete as on Turnip.
  - The draw sequence is identical on both drivers. The full-screen composite is VS `93F0150CBD1C14D9` / PS `B0302158BCD42BBE`, which samples:
    - the 320×180 blur (0x0757E000)
    - the depth texture (0x066A1000, `k_24_8_FLOAT` → R32F)
    - the scene (0x079F8000)
  - It writes the main RT. The copy of that RT right after it (to 0x071A4000/0x071A5000) is a single constant colour on Qualcomm (`0B0C1AFF` / `566BA3FF`) but varied on Turnip.
  - The depth-only passes right after it (PS `14C10A4E…`, `95626B9B…`) sample the same depth texture and give normal output on Qualcomm, so the depth texture is probably fine. The composite shader itself is suspect (constant UVs/param-gen or a fog factor saturating).
  - `wet_vk_allow_reverse_z = false` changes nothing (the composite is still constant), so it stays at the default (true).
- **1.0.9 additions** (overlays):
  - `wet_dump_shaders_filter` (default `93F0150CBD1C14D9,B0302158BCD42BBE`) / `wet_dump_shaders_dir` (default `/storage/emulated/0/WET Android/logs/shaders`) write each matching shader's ucode disassembly + binary and the SPIR-V of every translation (pipeline cache overlay).
  - `wet_probe_ps` (default `B0302158BCD42BBE`): in traced frames, probes every draw with that PS. It logs VS/PS constants, bool/loop constants, the interpolator mask, `ps_param_gen`, `SQ_PROGRAM_CNTL` / `SQ_CONTEXT_MISC`, and the three textures with GPU read-back (R32F images get min/max/mean/NaN stats). Textures get `TRANSFER_SRC` while this is set.
  - `wet_vk_float_controls` (added in 1.0.8) is the one switch left to try on Qualcomm.
- **Rubi's legs (Turnip):**
  - No skipped or failed draws in the stats (placeholder only during loads).
  - No VS uses dynamic constant addressing (max 16 constants), so skinning isn't done with constant-indexed bones in the VS.
  - The game may not be submitting the legs at all: a CPU-side skinning or visibility result could go wrong in the recompiled VMX code under SIMDe on ARM (no `SIMDE_FAST_*` flags are set). This needs a different trace (e.g. per-draw vertex-buffer addresses or a CPU-side check).
- **Launcher credits (1.0.9, `config/PortBrandingConfig.kt`):**
  - main-screen line "Android wrapper by Hailgames · WET recomp by Sydgaming and Claude AI"
  - credits title "Sydgaming"
  - links: YouTube `@sydgamingdb`, GitHub `yuriaaaaa`, WetRecomp (nikolaygorb), Hailgames (Telegram)
  - the footer credits WetRecomp/nikolaygorb and the Hailgames wrapper

## Findings from 1.0.9 (logs `restuff_20261008_003550` stock, `_004007` stock, `_004345` Turnip)
- The user's second and third runs used `vk_allow_reverse_z = false`; the real cvar is `wet_vk_allow_reverse_z`, so they ran with defaults.
- **Grey world (Qualcomm) = PsParamGen pixel position is (0,0) for every pixel.**
  - All three inputs of PS `B0302158BCD42BBE` read back the same on both drivers (blur, depth R32F stats, scene).
  - In 4 of 4 stock traces, the composite's output (next colour resolve to 0x071A4000) equals the scene texture's texel (0,0) exactly (e.g. T#23: scene `BF493628` → output `283649FF`).
  - The PS gets its UVs only from param gen (`SQ_PROGRAM_CNTL` param_gen=1, `SQ_CONTEXT_MISC` param_gen_pos=0, no interpolators): UV = |r0.xy| / (1280, 720). VS `93F0150CBD1C14D9` writes only position, so the pipeline has zero varyings.
  - The SPIR-V (dumped, validated) is correct; the Qualcomm driver/compiler gets `floor(gl_FragCoord.xy)` (or the FrontFacing select around it) wrong in this pipeline.
- **Legs (all characters, on the ground) = shader-written depth not scaled for float24.**
  - Frame order on Turnip T#9: depth prepass d25–d331, colour d332–d642, depth resolve `c0` (→ 0x06BAC000), shadow-volume/stencil passes on another surface, then **d710 restores depth from the texture** (`dc=00100376`, ALWAYS + write), then characters etc. d711–d838 with GEQUAL.
  - With host render targets, D24FS8 depth lives in host [0, 0.5] (`GetHostViewportInfo(full_float24_in_0_to_1)` halves the viewport range), but the viewport doesn't apply to `gl_FragDepth`. The SPIR-V translator only rescaled oDepth in the float24-conversion modes, so the restored depth was 2× (much closer in reversed Z).
  - Near floor behind standing legs then wins the depth test; legs over far background (jumping, ragdolls) show. The DXBC translator does this scaling in `CompletePixelShader_DSV_DepthTo24Bit`.
- **Frame rate:** gameplay runs at about 5–12 guest frames/s on both drivers (from `draws/60f` timestamps, 600–1400 draws/frame). The presenter painted about 600 times a second on Turnip (FIFO present doesn't block there) against about 100 on stock: `WaitForUITickFromUIThread` is a no-op off Windows, and the on-screen controls keep the UI thread repainting.

## Changes in 1.0.10
- **Legs fix** (`spirv_translator_rb.cpp` overlay, `CompleteFragmentShaderInMain`): if the PS writes depth and isn't in a float24-conversion mode, `gl_FragDepth *= 0.5` when `kSysFlag_DepthFloat24` is set.
- **Qualcomm param-gen variants** (`spirv_translator.h/.cpp`, `pipeline_cache.cpp`, `command_processor.cpp` overlays):
  - new `Modification::pixel.wet_param_gen_variant : 4` (bits 49–52 of the PS modification): 1 = dummy interpolator (command processor adds interpolator 15, or 14, to both masks when the mask was 0; the PS reads its W as param-gen W); 2 = no gl_FrontFacing; 4 = load gl_FragCoord as a vector and floor XY at once; 8 = no float-controls execution modes.
  - `wet_param_gen_variant` (default -1 = auto). Auto on `VK_DRIVER_ID_QUALCOMM_PROPRIETARY` tries 1, 2, 4, 8, 15. Each traced frame that draws a `wet_probe_ps` PS with param gen is judged at the next colour resolve of the same RT: all 8 samples equal (with varied input textures) = fail, otherwise lock. The trace interval is capped at 240 while searching.
  - The working variant is appended to `wet_gpu_workaround_file` (default `/storage/emulated/0/WET Android/gpu_workarounds.txt`) as `param_gen_variant qcom:<deviceID>:<driverVersion> <n>` and reused on later launches. Delete the file to search again.
  - All variants were translated offline with a host harness (scratchpad `hostspv/`, the SDK translator built for x86 with stubs) and pass `spirv-val --target-env vulkan1.2 --scalar-block-layout`; variant 0 matches the device's dumped SPIR-V except for 2x-MSAA sample bits.
- **UI repaint cap** (`src/ui/presenter.cpp` overlay): `wet_ui_paint_max_hz` (default 60) paces UI-thread paints off Windows.
- **Diagnostics:**
  - trace lines gain `pg=r<reg>/v<variant>` and `odepth=`
  - `WETDBG perf/60f` line: fps, ms/frame, GPU-thread time in draws/resolves, time blocked on fences
  - `wet_probe_png` (default 3) / `wet_probe_png_dir` (default `.../logs/frames`) save the probed pass's textures (scene, blur, depth) as PNG (stored deflate, ≤640 px wide)

## Findings from 1.0.10 (logs `restuff_20261008_022704` and `_022832`, stock driver)
- Variant 1 (dummy interpolator), 2 (no FrontFacing) and 4 (vector FragCoord) all gave a uniform composite output. **Variant 8, no float-controls execution modes (SignedZeroInfNanPreserve / DenormFlushToZero / RoundingModeRTE) in the PS, works.** `gpu_workarounds.txt` holds `param_gen_variant qcom:44050001:80320001 8`.
- PNG snapshots show Rubi standing with legs on both drivers' scenes (stock here); the 1.0.10 PNGs have R and B swapped (fixed in 1.0.11).
- **Performance:** `WETDBG perf/60f` in gameplay reads 4.4–7.7 fps, GPU thread spends 90–150 ms/frame inside `IssueDraw` for 700–1250 draws (~130 µs per draw), with no time blocked on fences. So the bottleneck is CPU work in the GPU command thread, not the GPU. Menus at 51 draws/frame run at 500 fps (1.4 µs/draw), so the cost scales with data, not a fixed per-draw overhead.
- Main suspect: `clear_memory_page_state = true` (launcher default, also in WetRecomp's desktop `hardware.toml`). At every frame end `SetSystemPageBlocksValidWithGpuDataWritten` drops the valid bit of all CPU-uploaded pages, so every vertex/index page used by a draw is re-uploaded from guest memory every frame. 1.0.11 measures it; the user is testing `clear_memory_page_state = false` on Turnip.

## Changes in 1.0.11
- `kWetParamGenSearchOrder` = {8, 15, 1, 2, 4}.
- `WETDBG perf/60f draw stages (ms/frame)`: setup, prims+shaders, textures, rts, pipeline, consts+bindings, vertices, draw, plus shared memory requests/MB requested, MB uploaded and ranges per frame, and CPU writes to watched memory (count and MB). Counters live in a new `src/graphics/shared_memory.cpp` overlay (`g_wet_shm_*` atomics).

## Findings from 1.0.11 (log `restuff_20261008_024848`, stock driver, default options)
- Variant 8 is applied from `gpu_workarounds.txt` at start; the user reports no graphical glitches and working saves.
- Busy gameplay: 5–10 fps, with 50–127 ms per frame inside `IssueDraw`. Stage split per frame: prims+shaders 11–61 ms, vertices 16–55 ms, textures 1–18 ms, everything else under 4 ms.
- Shared memory per frame: 900–3000 requests, **18–48 MB uploaded** in 550–1750 ranges. CPU writes to watched memory: 34–119 per frame (8–30 MB invalidated, widened to 256 KB).
- The uploads are the cost of `clear_memory_page_state = true`, which re-uploads every CPU-uploaded page (vertex and index data) each frame. Next test: the same run with `clear_memory_page_state = false`. If it's clean, make false the launcher default and look at the remaining CPU write faults.

## Findings from 1.0.12 (log `restuff_20261008_030702`, stock, `clear_memory_page_state = false`)
- Uploads fell from 18–48 to 3–14 MB/frame, but the time inside `IssueDraw` barely moved: prims+shaders 10–80 ms and vertices 14–90 ms per frame, with 1200–3600 `RequestRange` calls per frame.
- That suggests a fixed per-request cost rather than data volume. The only fixed costs in `RequestRanges` are a vector allocation and taking the global critical region, which is shared with the guest threads (100–150 CPU write faults per frame, the audio worker each audio frame, kernel calls). Hence the 1.0.13 fast path and lock-wait timing.
- Audio: no underrun messages in the log. The audio worker takes the same global lock every audio frame, so GPU-thread lock hold times probably cause the music stutter.

## Findings from 1.0.13 (logs `wetrecomp_20261008_033023` and `_033249`)
- **"Can't save":** the device slot order varied between boots. The phone exposes three SDL gamepads: "Xbox Series X Controller", "RB-HP160 Consumer Control" (Bluetooth headphones' media keys) and "Restuff Virtual Pad" (the touch overlay, slot 2 on every boot). `SlotAssignment` maps device ordinal to guest user.
  - When the headphones landed in slot 0 (both 1.0.13 runs, and 1.0.9's `_004345`), Start on the Xbox pad came from user 1. The game called `XamShowSigninUI` (logged as broadcast `0xA`, XN_SYS_SIGNINCHANGED), the SDK only signs in user 0, and the game went straight to chapter 1 without `XamShowDeviceSelectorUI` or any `save:` mount.
  - The runs that saved had the Xbox pad in slot 0: context 0x8001 went to 2 (main menu), then the device selector, then `save:` mounted over `\Device\Content\N`.
- **Performance after the fast path:** about 70–75% of `RequestRanges` calls are lock-free. The rest still wait **15–100 ms per frame** on the global critical region, and uploads, which take the lock again in `MakeRangeValid` and `EnablePhysicalMemoryAccessCallbacks`, cost 10–85 ms. CPU write faults run at 30–100 per frame (7–25 MB invalidated), and the game's job threads also use the global lock for kernel objects. Next: batch each draw's ranges into one `RequestRanges` call, and cut lock holds in the fault path and `UploadRanges`.

## Findings from 1.0.15 and changes in 1.0.16
- **Cause of the lock waits:** `MMIOHandler::ExceptionCallback` (`src/system/mmio_handler.cpp`) took the global critical region on every write fault to watched guest memory and then called `memory::QueryProtect`. On Linux/Android that reads and parses all of `/proc/self/maps` with `std::ifstream` (`FindEntryForAddress` in `memory_posix.cpp`). The write watches split the guest mappings into many VMAs, so that is thousands of lines.
  - The GPU thread's lock wait tracks the fault count per 60-frame window: correlation 0.86 in `wetrecomp_20261008_040801` (1.0.15) and 0.92 in `_035133` (1.0.14).
  - That works out to a median of 0.71 and 0.47 ms of GPU-thread wait per fault.
  - Guest threads that fault (and the audio worker, and kernel-object calls) were serialized behind the same scans, which fits the music and cutscene-load stutter.
- **1.0.16 fault path** (new overlays `src/system/mmio_handler.cpp` and `src/system/xmemory.cpp`):
  - The handler calls the access-violation callback (`Memory::AccessViolationCallback` → `PhysicalHeap::TriggerCallbacks`) first, under the lock as before. The watch bookkeeping it reads is protected by the same lock.
  - `QueryProtect` now runs only when the callback can't handle the fault: real access violations and read faults.
  - When another thread already cleared the watch (`TriggerCallbacks` finds nothing watched), `AccessViolationCallback` retries the store once, tracked by a thread-local page and a 100 ms window. A second fault on the same page goes to the existing stale-protection recovery path as before. This avoids the recovery path's unlocked `mprotect` racing with the GPU thread re-watching the page.
- **Commit path** (`src/core/memory_posix.cpp`): `AllocFixed`'s commit on an existing mapping (`MAP_FIXED_NOREPLACE` → `EEXIST`) calls `mprotect` directly instead of first checking with `IsRangeFullyMapped`, which also parsed `/proc/self/maps`. `mprotect` fails with `ENOMEM` on unmapped pages anyway.
- **New diagnostics:**
  - The `perf/60f draw stages` line ends with `write faults N per frame (X ms each, N slow)`. The time is measured from fault entry, including the lock wait; the counters `rex::runtime::g_wet_fault_*` are exported from `librexruntime.so` and read by the GPU plugin.
  - A new `WETDBG perf/60f lock waits by holder` line lists the five threads the GPU thread waited behind longest, by name and TID (from `/proc/self/task/<tid>/comm`). The owner TID is read from the bionic `pthread_mutex_t` (offset 4 on LP64) at the first failed `try_lock` in `WetAcquireGlobalLockSpinning`.
- Next, if dips remain: use the lock-holder line to find the next holder, then look at the texture stage (6–26 ms per frame) and at batching each draw's vertex ranges into one `RequestRanges` call.

## Build hygiene
- `scripts/apply_overlays.sh` skips identical files (`cmp -s`). Rewriting overlay headers bumps their mtimes and forces a full 25-minute rebuild of the recompiled code.
- SDK overlays in use:
  - the original port set
  - `src/graphics/vulkan/command_processor.cpp`, `pipeline_cache.cpp` and `texture_cache.cpp`
  - `src/graphics/pipeline/shader/spirv_translator_fetch.cpp` (the 1.0.7 fix)
  - `src/graphics/pipeline/shader/spirv_translator.cpp`, `spirv_translator_rb.cpp`, `include/rex/graphics/pipeline/shader/spirv_translator.h` (1.0.10; the header is graphics-only, so no full rebuild)
  - `src/ui/presenter.cpp` (1.0.10)
  - `src/graphics/shared_memory.cpp` (1.0.11)
  - `src/input/input_system.cpp` (1.0.14)
  - `src/system/mmio_handler.cpp` and `src/system/xmemory.cpp` (1.0.16; both in `librexruntime.so`, no header changes)
  - `src/system/function_dispatcher.cpp`
  - new file `src/graphics/vulkan/wet_tex_probe.h`, included only by the two Vulkan overlay files, so changing it doesn't trigger a full rebuild
- Quick compile check of single SDK objects: `ninja rexglue-sdk/src/graphics/CMakeFiles/rexgpu-xenos.dir/<subdir>/<file>.cpp.o` in `build/android/arm64-v8a` (about 25 s).

## Other known issues
- **Vortek:** fails with "Failed to get all Vulkan instance function pointers". Low priority, since it targets non-Adreno GPUs.
- **Crash on quitting the game:** SIGABRT from `PosixCondition<Thread>::QueueUserCallback`, called by `KernelState::TerminateTitle` from `ReXApp::OnClosing`. Harmless.
- **Mali-G57 (the friend's Xiaomi):** the SDK always requires `vertexPipelineStoresAndAtomics`; the cvar that would relax it is deprecated and ignored. Supporting that phone needs engine changes.
- **Audio/subtitle sync (reported with 1.0.6):** in sync on Turnip; slightly out of sync with the stock Qualcomm driver. Not investigated yet.
- **Intro movies:** still to be confirmed now that textures work (the 1.0.6 probe showed a constant black YUV frame early on).

## Getting logs from the phone
1. Grant WET **All files access** in Android Settings.
2. The engine then writes session logs to `Internal storage/WET Android/logs/wetrecomp_*.log` (`restuff_*.log` before 1.0.13), plus the matching `.toml`. The launcher keeps the 10 newest.
3. A native crash backtrace also goes to `<files>/last_crash.txt` (shown on the app's Diagnostics screen).
4. Resolve offsets in a backtrace offline against `build/android/arm64-v8a/librestuff.so.unstripped` and `librexruntime.so.unstripped`.

## Timings
- rexglue CLI (host): about 8 min
- codegen: about 5 min (475 files, 248 MB)
- native NDK build: about 25 min for a full build (a header change also triggers one); about 3–4 min when only graphics or system `.cpp` files change
- Gradle: under 2 min

## Network
The cloud environment needs **Custom** network access with these allowed domains, plus the default package-manager list:
- `dl.google.com`
- `maven.google.com`
- `repo.maven.apache.org`
- `repo1.maven.org`
- `plugins.gradle.org`
- `plugins-artifacts.gradle.org`
- `drive.google.com` and `drive.usercontent.google.com` (for shared files)

`services.gradle.org` stays blocked, so use the preinstalled `/opt/gradle` (8.14.3) instead of `./gradlew` (8.9). It works with AGP 8.7.3 and Kotlin 2.0.21.

## Workarounds that were needed
1. **Host codegen with clang 18.** The box has clang 18 and libstdc++ 13; clang 18 reports `__cpp_concepts` 201907, which hides `std::expected`.
   - Add `-U__cpp_concepts -D__cpp_concepts=202002L -Wno-macro-redefined -Wno-builtin-macro-redefined` to `CMAKE_CXX_FLAGS`.
2. **Host build without X11/Wayland dev packages.** apt is blocked. Build the CLI from a *copy* of the SDK (`build/rexglue-sdk-host`), so the Android tree stays untouched:
   - Set SDL X11/Wayland/ALSA/Pulse/PipeWire to OFF in `thirdparty/CMakeLists.txt`.
   - Make `pkg_check_modules(X11_XCB …)` and `pkg_check_modules(WAYLAND …)` non-REQUIRED in `src/ui/CMakeLists.txt`.
   - Add stub `X11/Xlib-xcb.h` and `wayland-client.h` (opaque `wl_display` / `wl_surface`).
   - Link with `-lX11-xcb -lX11` from symlinks to the runtime `.so.1` files.
3. **Maven Central returns HTTP 429.** Run Gradle with `--no-parallel -Dorg.gradle.internal.repository.max.retries=10 -Dorg.gradle.internal.repository.initial.backoff=4000` and retry.
4. **Library stripping.** `scripts/build_android_native.sh` handles both cases:
   - It strips `librexruntime.so` (92 MB to 12 MB) and keeps `build/android/arm64-v8a/librexruntime.so.unstripped`.
   - It strips `librestuff.so` into `librestuff.stripped.so` instead of in place.
   - AGP can't strip because its default NDK (27.0) isn't installed.

## Checks done on the build
- All 11 `.so` are AArch64.
- Every undefined dynamic symbol resolves within each library's NEEDED closure against NDK API-26 stubs.
- SDL3, its `JNI_OnLoad` and its 67 `Java_org_libsdl_*` exports live in `librexruntime.so`, loaded as a dependency of `librestuff.so`.
- Every SDL `RegisterNatives` table matches the Java natives (checked in the source and in the compiled dex).
- `:app:testReleaseUnitTest` passes (15 tests, including EngineOverridesTest).
- `apksigner verify` and `zipalign -c -P 16` both pass.
- The download page's six served parts reassemble to the zip's SHA-256 (checked after every publish).
