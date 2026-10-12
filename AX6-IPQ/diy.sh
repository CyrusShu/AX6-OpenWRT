#!/bin/bash
# Git稀疏克隆，只克隆指定目录到本地
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl"
  repodir=$(echo "$repourl" | awk -F '/' '{print $(NF)}')
  cd "$repodir" || exit 1
  # --no-cone 才能同时稀疏检出目录和单文件（如 easytier 的 version.mk）
  git sparse-checkout init --no-cone
  git sparse-checkout set "$@"
  mv -f "$@" ../package/
  cd .. && rm -rf "$repodir"
}

# Add packages
# EasyTier 组网（稀疏克隆，menuconfig 里自选 easytier / easytier-noweb）
git_sparse_clone main https://github.com/fightroad/luci-app-easytier easytier easytier-noweb luci-app-easytier version.mk

# Socat 端口转发 LuCI（Lienol 版，兼容新版 socat，配置用 luci_socat 不冲突）
git_sparse_clone main https://github.com/Lienol/openwrt-package luci-app-socat

# PassWall 科学上网（xiaorouji 源，替换 feeds 自带版本）
rm -rf feeds/packages/net/{xray-core,v2ray-geoip,v2ray-geodata,v2ray-geosite,v2ray-geosite-ir,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf package/openwrt-passwall-packages package/openwrt-passwall
git clone --depth 1 https://github.com/xiaorouji/openwrt-passwall-packages package/openwrt-passwall-packages
git clone --depth 1 https://github.com/xiaorouji/openwrt-package package/openwrt-passwall

# frp：用官方预编译包替换 Imm 源码编译（避免 node/host 编 WebUI 失败）
# 保留 feeds 里 Imm 的 files/（init、uci），LuCI 仍用官方 luci-app-frpc
DIY_DIR="$(cd "$(dirname "$0")" && pwd)"
FRP_SRC_MK="$DIY_DIR/frp/Makefile"
FRP_DST_DIR="feeds/packages/net/frp"
if [ ! -f "$FRP_SRC_MK" ]; then
  echo "ERROR: missing $FRP_SRC_MK" >&2
  exit 1
fi
if [ ! -d "$FRP_DST_DIR" ]; then
  echo "ERROR: missing $FRP_DST_DIR (run feeds install first)" >&2
  exit 1
fi
cp -f "$FRP_SRC_MK" "$FRP_DST_DIR/Makefile"
echo "frp: using official prebuilt binary Makefile ($(grep '^PKG_VERSION:=' "$FRP_DST_DIR/Makefile"))"

# frpc：LuCI 启用开关 + 默认关闭（避免未配置时连 127.0.0.1:7000 反复重启）
chmod +x "$DIY_DIR/frp/patch_enable.sh"
"$DIY_DIR/frp/patch_enable.sh" \
  "feeds/packages/net/frp/files" \
  "feeds/luci/applications/luci-app-frpc/htdocs/luci-static/resources/view/frpc.js"
#git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
#git clone --depth 1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config
#git clone --depth 1 https://github.com/sirpdboy/luci-app-ddns-go package/ddnsgo
#git clone --depth 1 https://github.com/sbwml/luci-app-mosdns package/mosdns
#git clone --depth 1 https://github.com/sbwml/luci-app-alist package/alist
#git clone --depth=1  https://github.com/kenzok8/small-package package/small-package
#git_sparse_clone main https://github.com/kiddin9/kwrt-packages luci-app-zerotier
#git_sparse_clone main https://github.com/kiddin9/kwrt-packages vlmcsd
#git_sparse_clone main https://github.com/kiddin9/kwrt-packages luci-app-vlmcsd
#git_sparse_clone main https://github.com/kiddin9/kwrt-packages luci-app-socat

# 替换luci-app-openvpn-server imm源的启动不了服务！
#rm -rf feeds/luci/applications/luci-app-openvpn-server
#git_sparse_clone main https://github.com/kiddin9/kwrt-packages luci-app-openvpn-server
# 调整 openvpn-server 到 VPN 菜单
#sed -i 's/services/vpn/g' package/luci-app-openvpn-server/luasrc/controller/*.lua
#sed -i 's/services/vpn/g' package/luci-app-openvpn-server/luasrc/model/cbi/openvpn-server/*.lua
#sed -i 's/services/vpn/g' package/luci-app-openvpn-server/luasrc/view/openvpn/*.htm

#git clone -b js https://github.com/papagaye744/luci-theme-design package/luci-theme-design

#删除库中的插件，使用自定义源中的包。
#rm -rf feeds/luci/themes/luci-theme-argon
#rm -rf feeds/luci/applications/luci-app-argon-config
#rm -rf feeds/luci/applications/luci-app-ddns-go
#rm -rf feeds/packages/net/ddns-go
#rm -rf feeds/packages/net/alist
#rm -rf feeds/luci/applications/luci-app-alist

#修改默认IP
#sed -i 's/192.168.1.1/192.168.123.1/g' package/base-files/files/bin/config_generate

#修改主机名
#sed -i "s/hostname='ImmortalWrt'/hostname='Redmi-AX6'/g" package/base-files/files/bin/config_generate

# ================================================================
# 自定义增删包（本脚本运行时 cwd = openwrt/，.config 已就位、make defconfig 之前）
#   追加：naiveproxy / Tailscale / SmartDNS
#   去掉：ZeroTier / EasyTier（组网工具只留 Tailscale 一个）
# ================================================================
add_pkg() {
  if grep -q "^# CONFIG_PACKAGE_$1 is not set$" .config; then
    # -i.bak 再删，GNU sed（CI 的 ubuntu）和 BSD sed（macOS）都能跑
    sed -i.bak "s|^# CONFIG_PACKAGE_$1 is not set$|CONFIG_PACKAGE_$1=y|" .config && rm -f .config.bak
  else
    echo "CONFIG_PACKAGE_$1=y" >> .config
  fi
}
del_pkg() {
  sed -i.bak "s|^CONFIG_PACKAGE_$1=y$|# CONFIG_PACKAGE_$1 is not set|" .config && rm -f .config.bak
}

# ---------- 要的 ----------
add_pkg naiveproxy                          # PassWall 的 naive 节点
add_pkg tailscale                           # Tailscale 客户端
add_pkg luci-app-tailscale-community        # 它的 LuCI 面板
add_pkg smartdns                            # SmartDNS 核心
add_pkg luci-app-smartdns                   # SmartDNS LuCI
add_pkg luci-i18n-smartdns-zh-cn            # 中文界面
add_pkg luci-i18n-tailscale-community-zh-cn

# ---------- 不要的 ----------
del_pkg zerotier
del_pkg luci-app-zerotier
del_pkg luci-i18n-zerotier-zh-cn

del_pkg easytier-noweb                      # 二进制包名是 easytier-noweb，不是 easytier
del_pkg luci-app-easytier
del_pkg luci-i18n-easytier-zh-cn

# ---------- 可选：还想省空间就取消注释 ----------
# del_pkg frpc
# del_pkg luci-app-frpc
# del_pkg vlmcsd
# del_pkg luci-app-vlmcsd
# del_pkg luci-app-autoreboot
# del_pkg luci-app-ramfree
