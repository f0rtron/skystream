# QuickJS-NG Upgrade Guide for flutter_js_ng

## Architecture Overview

This forked package uses a **dual-engine** strategy (inherited from the upstream `flutter_js`):

| Platform | JS Engine | Source |
| :--- | :--- | :--- |
| Android | **QuickJS-NG** (upgraded) | Compiled from source via CMake/NDK |
| Windows | **QuickJS-NG** (upgraded) | Pre-built `quickjs_c_bridge.dll` |
| Linux | **QuickJS-NG** (upgraded) | Pre-built `libquickjs_c_bridge_plugin.so` |
| iOS | JavaScriptCore (Apple) | System framework (no change) |
| macOS | JavaScriptCore (Apple) | System framework (no change) |

## How to Upgrade the QuickJS-NG Source

### Android (Compiled from Source)
The Android build compiles QuickJS source files directly via CMake.
To upgrade:

1. Download the latest QuickJS-NG release from https://github.com/quickjs-ng/quickjs/releases
2. Replace the following files in `android/src/main/c/quickjs/`:
   - `quickjs.c` → QuickJS-NG's `quickjs.c`
   - `quickjs.h` → QuickJS-NG's `quickjs.h`
   - `cutils.c` → QuickJS-NG's `cutils.c`
   - `cutils.h` → QuickJS-NG's `cutils.h`
   - `libregexp.c` → QuickJS-NG's `libregexp.c`
   - `libregexp.h` → QuickJS-NG's `libregexp.h`
   - `libunicode.c` → QuickJS-NG's `libunicode.c`
   - `libunicode.h` → QuickJS-NG's `libunicode.h`
   - `libbf.c` → QuickJS-NG's `libbf.c`
   - `libbf.h` → QuickJS-NG's `libbf.h`
   - `quickjs-c-atomics.h` → QuickJS-NG's `quickjs-c-atomics.h`
3. The CMakeLists.txt and the C++ bridge (`libfastdev_quickjs_runtime.cpp`) remain unchanged.
4. Android will compile the new source automatically during `flutter build`.

### Windows and Linux (Pre-built Binaries)
These platforms use pre-built shared libraries. The GitHub Actions workflow
(`build_quickjs_ng.yml`) handles cross-compilation:

- **Windows**: Outputs `windows/shared/quickjs_c_bridge.dll`
- **Linux**: Outputs `linux/shared/libquickjs_c_bridge_plugin.so`

## GitHub Actions Workflow

Run the `Build QuickJS-NG Natives` workflow to rebuild all pre-built binaries.
The workflow:
1. Clones the QuickJS-NG source
2. Clones the flutter_js C bridge source
3. Cross-compiles for Windows (MSVC) and Linux (GCC)
4. Commits the updated binaries back to the repository

## Important Notes

- The C bridge layer (`libfastdev_quickjs_runtime.cpp`) wraps the QuickJS C API
  with Flutter-compatible function signatures. QuickJS-NG maintains API compatibility
  with the original QuickJS, so this bridge works without modifications.
- iOS and macOS are unaffected — they use Apple's JavaScriptCore, which is already
  one of the fastest JS engines available.
