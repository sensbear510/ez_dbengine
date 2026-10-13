#!/bin/bash
set -e

BUILD_DIR="build_linux"

echo "[1/3] Setting up build directory for CLI (Linux/macOS)..."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "[2/3] Running CMake configuration with Ninja..."
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release ..

echo "[3/3] Compiling EZ-Shell CLI..."
ninja

echo "-----------------------------------------------"
echo "Linux/macOS CLI Build Completed Successfully!"

cd ..

# If the CMakeLists.txt file does not specify a centralized output path, the migration logic will be preserved.
cp -f "$BUILD_DIR/bin/ez_shell" . 2>/dev/null || true
cp -f "$BUILD_DIR/bin/ez_test_agent" . 2>/dev/null || true

echo "✨ Copied binaries to $(pwd)"