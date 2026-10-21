#!/bin/bash
set -e

echo "[*] Setting up Node.js FFI Environment (Project Linux Store)"

# 1. Resolve absolute path of project root (two levels up from ffi/node.js)
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LINUX_STORE="$PROJECT_ROOT/.linux_node_modules"

mkdir -p "$LINUX_STORE"

# 2. Install Linux-native Koffi if not already present in the dedicated directory
if [ ! -d "$LINUX_STORE/node_modules/koffi" ]; then
    echo "[*] Installing Linux-native Koffi into $LINUX_STORE..."
    cp package.json "$LINUX_STORE/"
    (cd "$LINUX_STORE" && npm install)
fi

# 3. Ensure the current directory uses a symlink pointing to project .linux_node_modules
#    Replace any accidental physical node_modules (e.g. from Windows) with symlink
if [ -L "node_modules" ]; then
    ln -sfn "$LINUX_STORE/node_modules" node_modules
elif [ -d "node_modules" ]; then
    echo "[!] Existing physical node_modules found. Replacing with symlink to project .linux_node_modules..."
    rm -rf node_modules package-lock.json
    ln -s "$LINUX_STORE/node_modules" node_modules
else
    ln -s "$LINUX_STORE/node_modules" node_modules
fi

# 4. Strictly verify libez_dbengine.so exists in the current directory (managed by root build_linux.sh, local copies forbidden)
SO_FILE="./libez_dbengine.so"
if [ ! -f "$SO_FILE" ]; then
    echo "❌ Error: '$SO_FILE' not found in current directory!"
    echo "💡 Please run './build_linux.sh' from the project root first to compile and distribute the latest library."
    exit 1
fi
echo "[OK] Dynamic library verified: $SO_FILE"

# 5. Set NODE_PATH to ensure the runtime resolves modules correctly
export NODE_PATH="$LINUX_STORE/node_modules"

# 6. Execute benchmark test
echo "🚀 Executing ez_stress_master (Node.js Native via Koffi)..."
node ez_stress_master.js