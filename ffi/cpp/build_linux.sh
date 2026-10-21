#!/usr/bin/env bash
set -e

echo "===================================================="
echo "[*] Building C++ FFI Targets for Linux"
echo "===================================================="

CPP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$CPP_DIR/../.."
RUN_LINUX="$CPP_DIR/run_linux"
BUILD_DIR="${CPP_DIR}/build_linux"

mkdir -p "$RUN_LINUX"

# 1. Check and acquire libez_dbengine.so
SO_TARGET="$RUN_LINUX/libez_dbengine.so"
if [ ! -f "$SO_TARGET" ]; then
    SO_SOURCE="$ROOT_DIR/build_linux/lib/libez_dbengine.so"
    if [ -f "$SO_SOURCE" ]; then
        echo "[*] Copying libez_dbengine.so from $SO_SOURCE..."
        cp -f "$SO_SOURCE" "$RUN_LINUX/"
    else
        echo "❌ [Error] libez_dbengine.so not found!"
        echo "👉 Please run './build_linux.sh' at project root first."
        exit 1
    fi
fi
echo "✅ [OK] Dynamic library verified: $SO_TARGET"

# 2. Copy test datasets
if [ -f "$ROOT_DIR/daily_2026-03-19.csv" ]; then
    cp -f "$ROOT_DIR/daily_2026-03-19.csv" "$RUN_LINUX/"
fi

# 3. Invoke CMake to build test binaries
echo "[*] Compiling C++ binaries..."

# If CMakeCache.txt exists and contains Windows drive paths, purge automatically to prevent cross-platform conflicts
if [ -f "$BUILD_DIR/CMakeCache.txt" ]; then
    if grep -q "[A-Za-z]:/" "$BUILD_DIR/CMakeCache.txt" 2>/dev/null; then
        echo "🧹 [Clean] Detected foreign Windows CMakeCache, purging build directory..."
        rm -rf "$BUILD_DIR/"
    fi
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release

echo "===================================================="
echo "🎉 Linux C++ Build Complete!"
echo "📍 Output directory: $RUN_LINUX"
echo "👉 Run with: cd $RUN_LINUX && ./ez_stress_master"
echo "===================================================="
cd "$RUN_LINUX"
./ez_stress_master
cd "$CPP_DIR"