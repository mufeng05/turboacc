#!/usr/bin/env bash
# shellcheck disable=SC2016

trap 'rm -rf "$TMPDIR"' EXIT
TMPDIR=$(mktemp -d) || exit 1

if ! [ -d "./package" ]; then
    echo "./package not found"
    exit 1
fi

kernel_versions="$(find "./include" | sed -n '/kernel-[0-9]/p' | sed -e "s@./include/kernel-@@" | sed ':a;N;$!ba;s/\n/ /g')"
if [ -z "$kernel_versions" ]; then
    kernel_versions="$(find "./target/linux/generic" | sed -n '/kernel-[0-9]/p' | sed -e "s@./target/linux/generic/kernel-@@" | sed ':a;N;$!ba;s/\n/ /g')"
fi
if [ -z "$kernel_versions" ]; then
    echo "Error: Unable to get kernel version, script exited"
    exit 1
fi
echo "kernel version: $kernel_versions"

kernel_full_versions=""
for kv in $kernel_versions; do
    kernel_file=""
    if [ -f "./include/kernel-$kv" ]; then
        kernel_file="./include/kernel-$kv"
    elif [ -f "./target/linux/generic/kernel-$kv" ]; then
        kernel_file="./target/linux/generic/kernel-$kv"
    fi
    full_ver="$kv"
    if [ -n "$kernel_file" ]; then
        patch_ver=$(sed -n "s/^LINUX_VERSION-${kv} *= *//p" "$kernel_file" | tr -d '[:space:]')
        if [ -n "$patch_ver" ]; then
            full_ver="${kv}${patch_ver}"
        fi
    fi
    kernel_full_versions="${kernel_full_versions:+$kernel_full_versions }$full_ver"
done
echo "kernel full version: $kernel_full_versions"

# Find the best matching patch directory based on version threshold.
# For directories hack-6.12, hack-6.12.78, hack-6.12.85 and kernel 6.12.80:
#   hack-6.12    (6.12.0)  <= 6.12.80 ✓
#   hack-6.12.78           <= 6.12.80 ✓  ← highest match, use this
#   hack-6.12.85           >  6.12.80 ✗
find_best_patch_dir() {
    local base_path="$1"
    local kv="$2"    # major.minor, e.g. 6.12
    local kfv="$3"   # full version, e.g. 6.12.80

    local best_dir=""
    local best_ver=""

    for dir in "$base_path"/hack-"${kv}" "$base_path"/hack-"${kv}".*; do
        [ -d "$dir" ] || continue
        local dv
        dv="$(basename "$dir")"
        dv="${dv#hack-}"

        # Normalize: "6.12" → "6.12.0" for comparison
        local cmp_ver="$dv"
        case "$dv" in *.*.*) ;; *) cmp_ver="${dv}.0" ;; esac

        # Skip if dir version > actual kernel version
        local smaller
        smaller="$(printf '%s\n%s' "$cmp_ver" "$kfv" | sort -V | head -n1)"
        [ "$smaller" = "$cmp_ver" ] || continue

        # Keep the highest match
        if [ -z "$best_ver" ]; then
            best_dir="$dir"
            best_ver="$cmp_ver"
        else
            local higher
            higher="$(printf '%s\n%s' "$best_ver" "$cmp_ver" | sort -V | tail -n1)"
            if [ "$higher" = "$cmp_ver" ]; then
                best_dir="$dir"
                best_ver="$cmp_ver"
            fi
        fi
    done

    echo "$best_dir"
}

# Find the best matching package patch directory based on version threshold.
# The suffix is a PKG_VERSION or PKG_SOURCE_DATE. For firewall4 2026-10-29 and
# directories patches-2026-10-26, patches-2026-10-28:
#   patches-2026-10-26 <= 2026-10-29 ✓
#   patches-2026-10-28 <= 2026-10-29 ✓  ← highest match, use this
# Without a match, the lede patches are used as they are.
find_best_pkg_patch_dir() {
    local base_path="$1"
    local pkg_ver="$2"   # PKG_VERSION or PKG_SOURCE_DATE, e.g. 1.1.7 or 2026-10-29

    local best_dir=""
    local best_ver=""

    [ -n "$pkg_ver" ] || return 0

    for dir in "$base_path"/patches-*; do
        [ -d "$dir" ] || continue
        local dv
        dv="$(basename "$dir")"
        dv="${dv#patches-}"

        # Skip if dir version > package version
        local smaller
        smaller="$(printf '%s\n%s' "$dv" "$pkg_ver" | sort -V | head -n1)"
        [ "$smaller" = "$dv" ] || continue

        # Keep the highest match
        if [ -z "$best_ver" ]; then
            best_dir="$dir"
            best_ver="$dv"
        else
            local higher
            higher="$(printf '%s\n%s' "$best_ver" "$dv" | sort -V | tail -n1)"
            if [ "$higher" = "$dv" ]; then
                best_dir="$dir"
                best_ver="$dv"
            fi
        fi
    done

    echo "$best_dir"
}

git clone --depth=1 --single-branch https://github.com/mufeng05/turboacc "$TMPDIR/turboacc" || exit 1

mkdir -p "./package/turboacc"
mkdir -p "./package/network/config/firewall/patches"
mkdir -p "./package/network/config/firewall4/patches"
mkdir -p "./package/network/utils/iptables/patches"
mkdir -p "./package/network/utils/nftables/patches"
mkdir -p "./package/libs/libnftnl/patches"

echo "Copying lede turboacc files..."

for kernel_version in $kernel_versions; do
    if [ "$kernel_version" = "6.18" ] || [ "$kernel_version" = "6.12" ] || [ "$kernel_version" = "6.6" ]; then
        cp -f "$TMPDIR/turboacc/lede/hack-$kernel_version/952-add-net-conntrack-events-support-multiple-registrant.patch" "./target/linux/generic/hack-$kernel_version"
        cp -f "$TMPDIR/turboacc/lede/hack-$kernel_version/953-net-patch-linux-kernel-to-support-shortcut-fe.patch" "./target/linux/generic/hack-$kernel_version"
        cp -f "$TMPDIR/turboacc/lede/hack-$kernel_version/982-add-bcm-fullconenat-support.patch" "./target/linux/generic/hack-$kernel_version"

        for patch in 983-add-bcm-fullconenat-to-nft.patch \
                     984-netfilter-reserve-unconfirmed-nat-tuples.patch \
                     985-netfilter-bcm-fullcone-reserve-expectation-early.patch; do
            if [ -f "$TMPDIR/turboacc/lede/hack-$kernel_version/$patch" ]; then
                cp -f "$TMPDIR/turboacc/lede/hack-$kernel_version/$patch" "./target/linux/generic/hack-$kernel_version"
            fi
        done

        if [ -f "$TMPDIR/turboacc/lede/pending-$kernel_version/613-netfilter_optional_tcp_window_check.patch" ]; then
            cp -f "$TMPDIR/turboacc/lede/pending-$kernel_version/613-netfilter_optional_tcp_window_check.patch" "./target/linux/generic/pending-$kernel_version"
        fi

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

mkdir -p "./package/turboacc/shortcut-fe/fast-classifier/patches"

kv_array=($kernel_versions)
kfv_array=($kernel_full_versions)

for i in "${!kv_array[@]}"; do
    kernel_version="${kv_array[$i]}"
    kernel_full_ver="${kfv_array[$i]}"

    patch_dir=$(find_best_patch_dir "$TMPDIR/turboacc/custom" "$kernel_version" "$kernel_full_ver")
    if [ -n "$patch_dir" ]; then
        echo "kernel $kernel_full_ver: using patches from $(basename "$patch_dir")"
        cp -f "$patch_dir"/*.patch "./target/linux/generic/hack-$kernel_version/"
    else
        echo "Warning: no matching custom patches found for kernel $kernel_full_ver"
    fi
done

# The files in custom/luci-app-turboacc replace those of lede, the rpcd backend is the ucode one
rm -rf "./package/turboacc/luci-app-turboacc/root/usr/libexec/rpcd"
cp -rf "$TMPDIR/turboacc/custom/luci-app-turboacc/." "./package/turboacc/luci-app-turboacc/"
chmod 755 "./package/turboacc/luci-app-turboacc/root/etc/init.d/turboacc" \
          "./package/turboacc/luci-app-turboacc/root/usr/libexec/luci-turboacc-status"
cp -f "$TMPDIR/turboacc/custom/fullconenat/Makefile" "./package/turboacc/fullconenat/"
cp -f "$TMPDIR/turboacc/custom/fullconenat-nft/Makefile" "./package/turboacc/fullconenat-nft/"

cp -f "$TMPDIR/turboacc/custom/patches/iptables/patches/900-bcm-fullconenat.patch" "./package/network/utils/iptables/patches/"
cp -f "$TMPDIR/turboacc/custom/shortcut-fe/fast-classifier/patches/001-fix-build.patch" "./package/turboacc/shortcut-fe/fast-classifier/patches/"

# Newer firewall4, nftables and libnftnl no longer accept some lede patches, use the rebased ones instead
fw4_ver="$(sed -n 's/^PKG_SOURCE_DATE:=//p' "./package/network/config/firewall4/Makefile" 2>/dev/null)"
patch_dir=$(find_best_pkg_patch_dir "$TMPDIR/turboacc/custom/patches/firewall4" "$fw4_ver")
if [ -n "$patch_dir" ]; then
    echo "firewall4 $fw4_ver: using patches from $(basename "$patch_dir")"
    cp -f "$patch_dir"/*.patch "./package/network/config/firewall4/patches/"
fi

nft_ver="$(sed -n 's/^PKG_VERSION:=//p' "./package/network/utils/nftables/Makefile" 2>/dev/null)"
patch_dir=$(find_best_pkg_patch_dir "$TMPDIR/turboacc/custom/patches/nftables" "$nft_ver")
if [ -n "$patch_dir" ]; then
    echo "nftables $nft_ver: using patches from $(basename "$patch_dir")"
    cp -f "$patch_dir"/*.patch "./package/network/utils/nftables/patches/"
fi

nftnl_ver="$(sed -n 's/^PKG_VERSION:=//p' "./package/libs/libnftnl/Makefile" 2>/dev/null)"
patch_dir=$(find_best_pkg_patch_dir "$TMPDIR/turboacc/custom/patches/libnftnl" "$nftnl_ver")
if [ -n "$patch_dir" ]; then
    echo "libnftnl $nftnl_ver: using patches from $(basename "$patch_dir")"
    cp -f "$patch_dir"/*.patch "./package/libs/libnftnl/patches/"
fi

# The libnftnl fullcone patch adds a source file, so the autotools files must be regenerated.
# lede sets PKG_FIXUP:=autoreconf for libnftnl and nftables, official OpenWrt does not always
for makefile in "./package/libs/libnftnl/Makefile" "./package/network/utils/nftables/Makefile"; do
    if [ -f "$makefile" ] && ! grep -q '^PKG_FIXUP:=.*autoreconf' "$makefile"; then
        sed -i '/^include $(INCLUDE_DIR)\/package.mk/i PKG_FIXUP:=autoreconf' "$makefile"
    fi
done

echo ""
echo "Finish"
echo ""
echo "Tip: 如果只需要全锥形 NAT (Full Cone NAT) 而不需要 turboacc 的其他功能，"
echo "     可以使用独立项目 openwrt-sonic-fullcone："
echo "     https://github.com/mufeng05/openwrt-sonic-fullcone"
exit 0
