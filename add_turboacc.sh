#!/usr/bin/env bash
# shellcheck disable=SC2016

trap 'rm -rf "$TMPDIR"' EXIT
TMPDIR=$(mktemp -d) || exit 1

if ! [ -d "./package" ]; then
    echo "./package not found"
    exit 1
fi

kernel_versions="$(find "./target/linux/generic" | sed -n '/kernel-[0-9]/p' | sed -e "s@./target/linux/generic/kernel-@@" | sed ':a;N;$!ba;s/\n/ /g')"
if [ -z "$kernel_versions" ]; then
    echo "Error: Unable to get kernel version, script exited"
    exit 1
fi
echo "kernel version: $kernel_versions"

git clone --depth=1 --single-branch https://github.com/mufeng05/turboacc "$TMPDIR/turboacc" || exit 1

mkdir -p "./package/turboacc"
mkdir -p "./package/network/config/firewall/patches"
mkdir -p "./package/network/config/firewall4/patches"
mkdir -p "./package/network/utils/iptables/patches"
mkdir -p "./package/network/utils/nftables/patches"
mkdir -p "./package/libs/libnftnl/patches"

echo "Copying lede turboacc files..."

for kernel_version in $kernel_versions; do
    if [ "$kernel_version" = "6.12" ] || [ "$kernel_version" = "6.6" ]; then
        cp -f "$TMPDIR/turboacc/lede/hack-$kernel_version/952-add-net-conntrack-events-support-multiple-registrant.patch" "./target/linux/generic/hack-$kernel_version"
        cp -f "$TMPDIR/turboacc/lede/hack-$kernel_version/953-net-patch-linux-kernel-to-support-shortcut-fe.patch" "./target/linux/generic/hack-$kernel_version"
        cp -f "$TMPDIR/turboacc/lede/hack-$kernel_version/982-add-bcm-fullconenat-support.patch" "./target/linux/generic/hack-$kernel_version"
        cp -f "$TMPDIR/turboacc/lede/hack-$kernel_version/983-add-bcm-fullconenat-to-nft.patch" "./target/linux/generic/hack-$kernel_version"
        cp -f "$TMPDIR/turboacc/lede/pending-$kernel_version/613-netfilter_optional_tcp_window_check.patch" "./target/linux/generic/pending-$kernel_version"

        if ! grep -q "CONFIG_SHORTCUT_FE" "./target/linux/generic/config-$kernel_version"; then
            echo "# CONFIG_SHORTCUT_FE is not set" >> "./target/linux/generic/config-$kernel_version"
        fi
    else
        echo "Unsupported kernel version: $kernel_version"
        exit 1
    fi
done

cp -rf "$TMPDIR/turboacc/lede/luci-app-turboacc" "./package/turboacc"
cp -rf "$TMPDIR/turboacc/lede/fullconenat" "./package/turboacc"
cp -rf "$TMPDIR/turboacc/lede/fullconenat-nft" "./package/turboacc"
cp -rf "$TMPDIR/turboacc/lede/shortcut-fe" "./package/turboacc"

cp -rf "$TMPDIR/turboacc/lede/patches/firewall/patches/"* "./package/network/config/firewall/patches/"
cp -rf "$TMPDIR/turboacc/lede/patches/firewall4/patches/"* "./package/network/config/firewall4/patches/"
cp -rf "$TMPDIR/turboacc/lede/patches/iptables/patches/"* "./package/network/utils/iptables/patches/"
cp -rf "$TMPDIR/turboacc/lede/patches/nftables/patches/"* "./package/network/utils/nftables/patches/"
cp -rf "$TMPDIR/turboacc/lede/patches/libnftnl/patches/"* "./package/libs/libnftnl/patches/"

echo "Applying custom patches..."

mkdir -p "./package/turboacc/luci-app-turboacc/root/usr/share/rpcd/ucode"
mkdir -p "./package/turboacc/luci-app-turboacc/root/usr/share/ucitrack"
mkdir -p "./package/turboacc/shortcut-fe/fast-classifier/patches"

for kernel_version in $kernel_versions; do
    cp -f "$TMPDIR/turboacc/custom/hack-$kernel_version/951-disable-unused-functions.patch" "./target/linux/generic/hack-$kernel_version"
done

cp -f "$TMPDIR/turboacc/custom/luci-app-turboacc/Makefile" "./package/turboacc/luci-app-turboacc/"
cp -f "$TMPDIR/turboacc/custom/luci-app-turboacc/root/etc/uci-defaults/turboacc" "./package/turboacc/luci-app-turboacc/root/etc/uci-defaults/"
cp -f "$TMPDIR/turboacc/custom/luci-app-turboacc/root/usr/share/rpcd/ucode/luci.turboacc" "./package/turboacc/luci-app-turboacc/root/usr/share/rpcd/ucode/"
cp -f "$TMPDIR/turboacc/custom/luci-app-turboacc/root/usr/share/ucitrack/luci-app-turboacc.json" "./package/turboacc/luci-app-turboacc/root/usr/share/ucitrack/"
rm -rf "./package/turboacc/luci-app-turboacc/root/usr/libexec"
cp -f "$TMPDIR/turboacc/custom/fullconenat/Makefile" "./package/turboacc/fullconenat/"
cp -f "$TMPDIR/turboacc/custom/fullconenat-nft/Makefile" "./package/turboacc/fullconenat-nft/"

cp -f "$TMPDIR/turboacc/custom/patches/iptables/patches/900-bcm-fullconenat.patch" "./package/network/utils/iptables/patches/"
cp -f "$TMPDIR/turboacc/custom/shortcut-fe/fast-classifier/patches/001-fix-build.patch" "./package/turboacc/shortcut-fe/fast-classifier/patches/"

echo "Finish"
exit 0
