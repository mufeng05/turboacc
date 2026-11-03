#!/usr/bin/env bash
# 检查本仓库的补丁能否打到官方 OpenWrt 某个分支的源码上。
#
# 克隆官方分支，用本仓库（当前检出的版本）运行 add_turboacc.sh，
# 再按 OpenWrt 编译时的方式（scripts/patch-kernel.sh，即 patch -f -p1，按文件名顺序）
# 把补丁打到各软件包的源码和通用内核上：
#   软件包：firewall、firewall4、iptables、nftables、libnftnl 的全部补丁
#   内核：  target/linux/generic 下的 files、backport、pending、hack
#
# 用法: check_patches.sh <OpenWrt 分支> [工作目录]
#   环境变量 DL_DIR：下载源码的缓存目录，默认为 <工作目录>/dl

set -euo pipefail

branch=$1
work=${2:-$(mktemp -d)}
repo=$(cd "$(dirname "$0")/../.." && pwd)
dl=${DL_DIR:-$work/dl}
ow=$work/openwrt
results=()
failed=0

mkdir -p "$work" "$dl"

echo "::group::克隆 OpenWrt $branch"
rm -rf "$ow"
git clone -q --depth=1 --branch "$branch" --filter=blob:none --sparse https://github.com/openwrt/openwrt.git "$ow"
git -C "$ow" sparse-checkout set include scripts target/linux/generic \
	package/network/config/firewall package/network/config/firewall4 \
	package/network/utils/iptables package/network/utils/nftables package/libs/libnftnl
echo "OpenWrt $branch: $(git -C "$ow" log -1 --format='%h %cd' --date=short)"
echo "::endgroup::"

echo "::group::运行 add_turboacc.sh"
# add_turboacc.sh 会从 GitHub 克隆本仓库，这里改为复制当前检出的版本
sed 's#^git clone --depth=1 --single-branch https://github.com/mufeng05/turboacc "$TMPDIR/turboacc" || exit 1$#cp -r "$TURBOACC_SRC" "$TMPDIR/turboacc" || exit 1#' \
	"$repo/add_turboacc.sh" > "$work/add_turboacc.sh"
if ! grep -q 'TURBOACC_SRC' "$work/add_turboacc.sh"; then
	echo "::error::add_turboacc.sh 中克隆本仓库的命令变了，请同步修改 check_patches.sh"
	exit 1
fi
(cd "$ow" && TURBOACC_SRC="$repo" bash "$work/add_turboacc.sh")
echo "::endgroup::"

# 与 OpenWrt 的 PatchDir 相同：用 scripts/patch-kernel.sh 依次应用各目录中的补丁
apply() {
	local name=$1 src=$2 dir log
	shift 2
	log=$work/$(echo "$name" | tr ' /' '__').log
	: > "$log"
	for dir in "$@"; do
		[ -d "$dir" ] || continue
		if ! "$ow/scripts/patch-kernel.sh" "$src" "$dir" >> "$log" 2>&1; then
			local bad
			bad=$(sed -n 's/^Patch failed!  Please fix \(.*\)!$/\1/p' "$log" | tail -n 1)
			echo "::error title=补丁打不上（$branch）::$name：${bad#"$ow/"}"
			grep -E '^(Hunk|patching file|[0-9]+ out of [0-9]+ hunks)' "$log" | tail -n 20 || true
			results+=("| $name | ❌ \`${bad#"$ow/"}\` |")
			failed=1
			return 0
		fi
	done
	results+=("| $name | ✅ $(grep -c '^Applying ' "$log" || true) 个补丁 |")
}

fetch() {   # <文件名> <sha256> <下载地址>...
	local file=$1 hash=$2 url
	shift 2
	if [ ! -f "$dl/$file" ]; then
		for url in "$@"; do
			curl -fsSL --retry 3 -o "$dl/$file.tmp" "$url" && mv "$dl/$file.tmp" "$dl/$file" && break
		done
	fi
	echo "$hash  $dl/$file" | sha256sum -c --quiet
}

mkvar() {   # <Makefile> <变量名>：读取 Makefile 中直接赋值的变量
	sed -n "s/^$2:=//p" "$1" | head -n 1
}

echo "::group::软件包"
for pkg in network/config/firewall network/config/firewall4 network/utils/iptables network/utils/nftables libs/libnftnl; do
	mk=$ow/package/$pkg/Makefile
	name=${pkg##*/}
	src=$work/src-$name
	rm -rf "$src"
	if [ "$(mkvar "$mk" PKG_SOURCE_PROTO)" = "git" ]; then
		# firewall3 / firewall4：取 Makefile 指定的提交
		ver=$(mkvar "$mk" PKG_SOURCE_VERSION)
		project=$(sed -n 's#^PKG_SOURCE_URL=$(PROJECT_GIT)/project/\(.*\)\.git$#\1#p' "$mk")
		git clone -q "https://git.openwrt.org/project/$project.git" "$src" ||
			git clone -q "https://github.com/openwrt/$project.git" "$src"
		git -C "$src" checkout -q "$ver"
		label="$name $(mkvar "$mk" PKG_SOURCE_DATE) (${ver:0:7})"
	else
		ver=$(mkvar "$mk" PKG_VERSION)
		file=$name-$ver.tar.xz
		fetch "$file" "$(mkvar "$mk" PKG_HASH)" \
			"https://netfilter.org/projects/$name/files/$file" "https://sources.openwrt.org/$file"
		mkdir -p "$src"
		tar -xJf "$dl/$file" -C "$src" --strip-components=1
		label="$name $ver"
	fi
	apply "$label" "$src" "$ow/package/$pkg/patches"
	rm -rf "$src"
done
echo "::endgroup::"

for kf in "$ow"/include/kernel-[0-9]* "$ow"/target/linux/generic/kernel-[0-9]*; do
	[ -f "$kf" ] || continue
	kv=${kf##*/kernel-}
	full=$kv$(sed -n "s/^LINUX_VERSION-$kv *= *//p" "$kf" | tr -d '[:space:]')
	echo "::group::内核 $full"
	file=linux-$full.tar.xz
	fetch "$file" "$(sed -n "s/^LINUX_KERNEL_HASH-$full *= *//p" "$kf" | tr -d '[:space:]')" \
		"https://cdn.kernel.org/pub/linux/kernel/v${kv%%.*}.x/$file" "https://sources.openwrt.org/$file"
	src=$work/linux-$full
	rm -rf "$src"
	mkdir -p "$src"
	tar -xJf "$dl/$file" -C "$src" --strip-components=1
	# 与 include/target.mk 中 GENERIC_*_DIR 的取法相同：有带版本号的目录时用它
	g=$ow/target/linux/generic
	dirs=()
	for d in backport pending hack; do
		if [ -d "$g/$d-$kv" ]; then dirs+=("$g/$d-$kv"); else dirs+=("$g/$d"); fi
	done
	for d in "$g/files" "$g/files-$kv"; do
		[ -d "$d" ] && cp -r "$d/." "$src/"
	done
	apply "内核 $full" "$src" "${dirs[@]}"
	rm -rf "$src"
	echo "::endgroup::"
done

{
	echo "### OpenWrt $branch（$(git -C "$ow" log -1 --format='%h %cd' --date=short)）"
	echo
	echo "| 源码 | 结果 |"
	echo "|---|---|"
	printf '%s\n' "${results[@]}"
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"

exit $failed
