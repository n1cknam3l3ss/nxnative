# Borderlands 3: Ultimate Edition - iOS Porting Status

## 1. Game Details
- **Title ID:** `01009970122E4000`
- **Version:** v196608 (v1.0.3)
- **Engine:** Unreal Engine 4.20.3
- **Graphics API:** NVN (translated to Metal Shading Language)
- **Total Translated Shaders:** 65,941

---

## 2. Crash Diagnostics & Fixes Applied

### A. Crash at `main+0x3d4fe70` (FMallocBinned3 Constructor)
- **Problem:**
  On boot, the game crashed with `[dm] CRASH sig=11 addr=0 pc=main+0x3d4fe70 lr=main+0x3d622f0` (`str x8, [x0]` where `x0 = 0`).
  Unreal Engine 4.20.3 has `GetDescriptiveName` at **slot 17** of the vtable. `ue_malloc.py` only supported slots 19 (UE 4.26/4.27), 22 (UE 5), and 26 (UE 5.6). Because slot 17 was unknown, `ue_malloc.py` failed to cut the `FMallocBinned3` constructor, causing the engine to attempt reserving its 37 GB pools directly on iOS.
- **Fix (commit `02585416`):**
  - `dm/tools/ue_malloc.py`: Added `LAYOUTS[17] = 'Unreal Engine 4.20'`.
  - `dm/host/hle_uemalloc.c`: Added `UE4_20` enum and layout definition:
    `[UE4_20] = { 17, 19, 3, 0, 4, 0, 5, 6, 7, { 8, 9, 10, 14 } }`.

### B. Address Region Reservation
- **Problem:**
  `-SwitchVirtualAddressSpaceSize=2048` in `game.tsv` caused `nninitStartup` to skip `AllocateAddressRegion`, leaving the virtual memory base at `0`. When the engine called `AllocateMemoryPages(0, 0xcd500000)`, it failed with `0xe03` (`ResultAddressRegionNotAvailable`).
- **Fix:**
  - Removed `game_args -SwitchVirtualAddressSpaceSize=2048` from `dm/games/01009970122E4000/game.tsv`.
  - Now `ue_region` automatically calculates and allocates the address region matching `alias_room()` (2.81 GB).

---

## 3. Releases & Distribution
- **Thin IPA (with UE 4.20 Fix):**
  - Release Tag: `bl3-fix-ue420`
  - GitHub URL: `https://github.com/switch-ports/shhhh/releases/tag/bl3-fix-ue420`
  - Parts: `Borderlands3.ipa.partaa` + `Borderlands3.ipa.partab` (combine via binary concat into `Borderlands3_thin.ipa`, ~2.88 GB).
- **RomFS Image:**
  - `romfs.img` (~20.3 GB) placed in `Documents/` or pushed via network/cable.

---

## 4. How to Continue Development on Mobile or Another Machine
- Repo: `https://github.com/switch-ports/shhhh` (branch: `main`)
- CI Pipeline: `.github/workflows/build_ipa.yml` runs on `macos-latest` with cached shaders (`cache_tag: bl3`).
- Any new agent session can read this file to immediately resume without re-diagnosing known issues.
