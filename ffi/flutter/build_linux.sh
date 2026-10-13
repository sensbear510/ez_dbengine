#!/usr/bin/env bash
set -e

echo "===================================================="
echo "[*] Building Flutter Stress App for Linux"
echo "===================================================="

FLUTTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$FLUTTER_DIR/../.."
RUN_LINUX="$FLUTTER_DIR/run_linux"
PKG_DIR="$FLUTTER_DIR/ez_dbengine"
TEST_APP_DIR="$FLUTTER_DIR/test/ez_stress_app"

mkdir -p "$RUN_LINUX"

# 1. Verify and ensure libez_dbengine.so is present in run_linux
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

# 2. Resolve fixed version dependencies
echo "[*] Resolving dependencies with flutter pub get..."
cd "$PKG_DIR"
flutter pub get

cd "$TEST_APP_DIR"
flutter pub get

# 3. Build full Linux Release Bundle via Flutter
echo "[*] Compiling Linux App via flutter build linux --release..."
flutter build linux --release

# 4. Sync Flutter bundle artifacts to run_linux
BUNDLE_DIR="$TEST_APP_DIR/build/linux/x64/release/bundle"
echo "[*] Syncing bundle artifacts into $RUN_LINUX..."
cp -rf "$BUNDLE_DIR/"* "$RUN_LINUX/"

# Ensure both application root and bundle internal lib directories hold .so
cp -f "$SO_TARGET" "$RUN_LINUX/lib/" 2>/dev/null || true

echo "===================================================="
echo "🎉 Linux Flutter App Build Complete!"
echo "📍 Output directory: $RUN_LINUX"
echo "👉 Run with: cd $RUN_LINUX && ./ez_stress_app"
echo "===================================================="
cd "$RUN_LINUX"
LIBGL_ALWAYS_SOFTWARE=1 DISPLAY=:0 ./ez_stress_app 
cd "$FLUTTER_DIR"