#!/usr/bin/env bash
set -e

echo "===================================================="
echo "[*] Building C# Stress Master for Linux"
echo "===================================================="

CS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$CS_DIR/../.."
RUN_LINUX="$CS_DIR/run_linux"

mkdir -p "$RUN_LINUX"

# 1. Ensure libez_dbengine.so is properly deployed in run_linux or project root
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

# 2. Publish standalone binary to run_linux
echo "[*] Publishing C# project to $RUN_LINUX..."
cd "$CS_DIR"
dotnet publish -c Release -r linux-x64 --self-contained false -o "$RUN_LINUX"

# 3. Copy test data file to run_linux if available
if [ -f "$ROOT_DIR/daily_2026-03-19.csv" ]; then
    cp -f "$ROOT_DIR/daily_2026-03-19.csv" "$RUN_LINUX/"
elif [ -f "$CS_DIR/daily_2026-03-19.csv" ]; then
    cp -f "$CS_DIR/daily_2026-03-19.csv" "$RUN_LINUX/"
fi

echo "===================================================="
echo "🎉 Linux C# Build Complete!"
echo "📍 Output directory: $RUN_LINUX"
echo "👉 Run with: cd $RUN_LINUX && ./ez_stress_master"
echo "===================================================="

cd "$RUN_LINUX"
./ez_stress_master
cd "$CS_DIR"