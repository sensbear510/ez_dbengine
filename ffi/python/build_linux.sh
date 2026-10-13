#!/usr/bin/env bash
set -e

echo "===================================================="
echo "[*] Setting up Python FFI Environment (Linux)"
echo "===================================================="

PY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$PY_DIR/../.."

# 1. 確保 libez_dbengine.so 就位
SO_TARGET="$PY_DIR/libez_dbengine.so"
if [ ! -f "$SO_TARGET" ]; then
    SO_SOURCE="$ROOT_DIR/build_linux/lib/libez_dbengine.so"
    if [ -f "$SO_SOURCE" ]; then
        echo "[*] Copying libez_dbengine.so from $SO_SOURCE..."
        cp -f "$SO_SOURCE" "$PY_DIR/"
    else
        echo "❌ [Error] libez_dbengine.so not found!"
        echo "👉 Please run './build_linux.sh' at project root first."
        exit 1
    fi
fi
echo "✅ [OK] Dynamic library verified: $SO_TARGET"

# 2. 複製測試資料
if [ -f "$ROOT_DIR/daily_2026-03-19.csv" ]; then
    cp -f "$ROOT_DIR/daily_2026-03-19.csv" "$PY_DIR/"
fi

echo "===================================================="
echo "🎉 Python Environment Ready!"
echo "👉 Run with: cd $PY_DIR && python3 test_ez_stress.py"
echo "===================================================="

cd "$PY_DIR"
python3 test_ez_stress.py
