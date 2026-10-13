#!/usr/bin/env bash
set -e

echo "===================================================="
echo "[*] Building Rust Stress Master for Linux"
echo "===================================================="

RUST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$RUST_DIR/../.."
RUN_LINUX="$RUST_DIR/run_linux"

mkdir -p "$RUN_LINUX"

# 1. 確保 libez_dbengine.so 就位
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

# 2. 複製測試資料
if [ -f "$ROOT_DIR/daily_2026-03-19.csv" ]; then
    cp -f "$ROOT_DIR/daily_2026-03-19.csv" "$RUN_LINUX/"
elif [ -f "$RUST_DIR/daily_2026-03-19.csv" ]; then
    cp -f "$RUST_DIR/daily_2026-03-19.csv" "$RUN_LINUX/"
fi

# 3. 執行 Cargo Release 編譯
echo "[*] Compiling via cargo build --release..."
cd "$RUST_DIR"
cargo build --release

# 4. 同步執行檔至 run_linux
cp -f "$RUST_DIR/target/release/ez_stress_master" "$RUN_LINUX/"

echo "===================================================="
echo "🎉 Linux Rust Build Complete!"
echo "📍 Output directory: $RUN_LINUX"
echo "👉 Run with: cd $RUN_LINUX && ./ez_stress_master"
echo "===================================================="

cd "$RUN_LINUX"
./ez_stress_master
cd "$RUST_DIR"