#!/bin/bash
set -e

PKG_NAME="ezdbutility"
PKG_VERSION="1.0.0"
PKG_ARCH="amd64"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUI_DIR="${SCRIPT_DIR}"

# 來源目錄 (Release Bundle)
SRC_DIR="${GUI_DIR}/run_linux/release"

# 🌟 關鍵修正：將打包骨架建在 Linux 原生 /tmp 下，徹底解決共享磁碟 chmod 777 無效的問題
DEB_BUILD_DIR="/tmp/${PKG_NAME}_build_${PKG_VERSION}_${PKG_ARCH}"
DEB_ROOT="${DEB_BUILD_DIR}/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}"

echo "=============================================================================="
echo "[ez_engine] Building Debian Package (.deb) for 1-Click Install ..."
echo "=============================================================================="

# 檢查來源目錄
if [ ! -d "${SRC_DIR}" ] || [ ! -f "${SRC_DIR}/ezdbutility" ]; then
    echo "❌ [Error] 找不到發布目錄或執行檔: ${SRC_DIR}/ezdbutility"
    echo "請先執行 ./build_linux_2.sh release 產出發布檔案！"
    exit 1
fi

# 1. 在 /tmp 建立乾淨的 DEBIAN 目錄骨架
rm -rf "${DEB_BUILD_DIR}"
mkdir -p "${DEB_ROOT}/DEBIAN"
mkdir -p "${DEB_ROOT}/opt/${PKG_NAME}"
mkdir -p "${DEB_ROOT}/usr/bin"
mkdir -p "${DEB_ROOT}/usr/share/applications"
mkdir -p "${DEB_ROOT}/usr/share/icons/hicolor/256x256/apps"

# 2. 複製發布檔案到 /opt/ezdbutility
echo "[*] 正在複製應用程式本體..."
cp -a "${SRC_DIR}/." "${DEB_ROOT}/opt/${PKG_NAME}/"

# 3. 建立命令列捷徑軟連結
ln -sf "/opt/${PKG_NAME}/ezdbutility" "${DEB_ROOT}/usr/bin/${PKG_NAME}"

# 4. 建立桌面選單啟動捷徑 (.desktop)
echo "[*] 正在建立桌面圖示捷徑..."
cat <<EOF > "${DEB_ROOT}/usr/share/applications/${PKG_NAME}.desktop"
[Desktop Entry]
Name=ezDBUtility
Comment=Craftsman Precision Database Utility Engine
Exec=/opt/${PKG_NAME}/ezdbutility
Icon=${PKG_NAME}
Terminal=false
Type=Application
Categories=Development;Database;
StartupNotify=true
EOF

# 5. 複製 App 圖示
if [ -f "${GUI_DIR}/assets/icons/icon.png" ]; then
    cp -f "${GUI_DIR}/assets/icons/icon.png" "${DEB_ROOT}/usr/share/icons/hicolor/256x256/apps/${PKG_NAME}.png"
elif [ -f "${GUI_DIR}/linux/flutter/ephemeral/icon.png" ]; then
    cp -f "${GUI_DIR}/linux/flutter/ephemeral/icon.png" "${DEB_ROOT}/usr/share/icons/hicolor/256x256/apps/${PKG_NAME}.png"
fi

# 6. 生成 control 設定檔
echo "[*] 正在生成 control 設定檔..."
cat <<EOF > "${DEB_ROOT}/DEBIAN/control"
Package: ${PKG_NAME}
Version: ${PKG_VERSION}
Section: utils
Priority: optional
Architecture: ${PKG_ARCH}
Depends: libgtk-3-0, zenity | kdialog, xdg-desktop-portal-gtk
Maintainer: ezLink.io <support@ezlink.io>
Description: ezDBUtility Workstation Desktop GUI
 Advanced high-performance multi-platform database workstation and relation studio.
EOF

# 7. 在原生 Linux 檔案系統精確設定權限 (0755)
chmod -R 0755 "${DEB_BUILD_DIR}"

# 8. 打包 .deb 檔案至 /tmp
echo "[*] 正在編譯打包 .deb 檔案..."
dpkg-deb --build --root-owner-group "${DEB_ROOT}"

# 9. 將產出的 .deb 移動至專案的 run_linux 目錄
TARGET_DEB_DIR="${GUI_DIR}/run_linux"
mkdir -p "${TARGET_DEB_DIR}"
mv -f "${DEB_BUILD_DIR}/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.deb" "${TARGET_DEB_DIR}/"

# 清理 /tmp 暫存
rm -rf "${DEB_BUILD_DIR}"

FINAL_DEB="${TARGET_DEB_DIR}/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.deb"

echo "=============================================================================="
echo "🎉 .deb 安裝包製作成功！"
echo "檔案位置: ${FINAL_DEB}"
echo "安裝指令: sudo apt install -y ${FINAL_DEB}"
echo "=============================================================================="