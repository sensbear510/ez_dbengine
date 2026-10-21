#!/bin/bash
set -e

# 1. Parameter check and build mode validation (Default: release)
MODE="release"
if [ "$1" = "debug" ]; then
    MODE="debug"
elif [ "$1" = "release" ] || [ -z "$1" ]; then
    MODE="release"
else
    echo "[ERROR] Invalid mode: $1"
    echo "Usage: $0 [release|debug]"
    exit 1
fi

echo "=============================================================================="
echo "[ez_engine] Building Linux GUI ($MODE) ..."
echo "=============================================================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUI_DIR="${SCRIPT_DIR}"

cd "${GUI_DIR}"

# 2. Execute Flutter Linux build
if [ "${MODE}" = "debug" ]; then
    flutter build linux --debug
else
    flutter build linux --release
fi

SRC_BUNDLE="${GUI_DIR}/build/linux/x64/${MODE}/bundle"

# 3. Target directory: ~/ez_dbengine/dbu/gui/run_linux/${MODE}
DEST_DIR="${HOME}/ez_dbengine/dbu/gui/run_linux/${MODE}"

mkdir -p "${DEST_DIR}"
echo "[*] Synchronizing runtime bundle to ${DEST_DIR} ..."
rsync -a --delete "${SRC_BUNDLE}/" "${DEST_DIR}/"

# 4. Normalize binary name to ezdbutility
if [ -f "${DEST_DIR}/gui" ]; then
    mv -f "${DEST_DIR}/gui" "${DEST_DIR}/ezdbutility"
fi

# Ensure executable permissions
chmod +x "${DEST_DIR}/ezdbutility"

echo "=============================================================================="
echo "[SUCCESS] Linux GUI ($MODE) Build Complete!"
echo "Runtime Path:"
echo "  ${DEST_DIR}/"
echo "Launch Command:"
echo "  ${DEST_DIR}/ezdbutility"
echo "=============================================================================="

# 5. Package release tarball (Release mode only)
if [ "${MODE}" = "debug" ]; then
    echo "[*] Debug mode active. Skipping archive packaging."
    exit 0
fi

echo ""
echo "=============================================================================="
echo "[ez_engine] Packaging Linux Release Bundle (.tar.gz) ..."
echo "=============================================================================="

ARCHIVE_DIR="${HOME}/ez_dbengine/dbu/gui/run_linux"
ARCHIVE_NAME="ezdbutility-linux-x64.tar.gz"

# Change directory and compress the release folder
tar -czf "${ARCHIVE_DIR}/${ARCHIVE_NAME}" -C "${ARCHIVE_DIR}" release

echo "[SUCCESS] Packaging Complete!"
echo "Release Package Location:"
echo "  ${ARCHIVE_DIR}/${ARCHIVE_NAME}"
echo "=============================================================================="