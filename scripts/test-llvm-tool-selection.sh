#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
	echo "usage: $0 LLVM_BIN/ CROSS_COMPILE" >&2
	exit 2
fi

llvm_bin=$1
cross_prefix=$2
case "$llvm_bin" in
	/*/) ;;
	*) echo "LLVM_BIN must be an absolute directory ending in /" >&2; exit 2 ;;
esac

test_dir=$(mktemp -d)
trap 'find "$test_dir" -type l -delete; rm -f "$database"; rmdir "$test_dir"' EXIT HUP INT TERM
database=$test_dir/database

read_tools()
{
	make -s -pn ARCH=arm CROSS_COMPILE="$cross_prefix" "$@" kernelversion > "$database"
}

require_tool()
{
	if ! grep -F -q -- "$1" "$database"; then
		echo "missing selected tool: $1" >&2
		exit 1
	fi
}

reject_tool()
{
	if grep -F -q -- "$1" "$database"; then
		echo "unexpected selected tool: $1" >&2
		exit 1
	fi
}

read_tools
require_tool 'CC = $(CROSS_COMPILE)gcc'
require_tool 'LD = $(CROSS_COMPILE)ld'
require_tool 'AR = $(CROSS_COMPILE)ar'

read_tools "LLVM=$llvm_bin" LLVM_IAS=1 CC=clang
require_tool "CC := ${llvm_bin}clang --target=arm-linux-androideabi -fgnuc-version=4.9.0"
require_tool "LD := ${llvm_bin}ld.lld"
require_tool "AR := ${llvm_bin}llvm-ar"
require_tool "NM := ${llvm_bin}llvm-nm"
require_tool "STRIP := ${llvm_bin}llvm-strip"
require_tool "OBJCOPY := ${llvm_bin}llvm-objcopy"
require_tool "OBJDUMP := ${llvm_bin}llvm-objdump"
require_tool "HOSTCC = gcc"
reject_tool "-no-integrated-as"

read_tools "LLVM=$llvm_bin" LLVM_IAS=0
require_tool "-no-integrated-as"
require_tool "--prefix=$(dirname "$cross_prefix")/"

PATH="$(dirname "$cross_prefix"):$PATH" cross_prefix=arm-linux-androidkernel- \
	read_tools "LLVM=$llvm_bin" LLVM_IAS=0
require_tool "CC := ${llvm_bin}clang --target=arm-linux-androideabi"
reject_tool "--prefix=$(dirname "$cross_prefix")/"

PATH="${llvm_bin%/}:$PATH" read_tools LLVM=1 LLVM_IAS=1
require_tool "CC := clang --target=arm-linux-androideabi"

cross_prefix= read_tools "LLVM=$llvm_bin" LLVM_IAS=1
require_tool "CC := ${llvm_bin}clang --target=arm-linux-gnueabi"

for tool in clang ld.lld llvm-ar llvm-nm llvm-strip llvm-objcopy llvm-objdump; do
	if [ "$tool" = clang ]; then
		ln -s "$(command -v clang)" "${test_dir}/${tool}-test"
	else
		ln -s "${llvm_bin}${tool}" "${test_dir}/${tool}-test"
	fi
done
PATH="$test_dir:$PATH" read_tools LLVM=-test LLVM_IAS=1
require_tool "CC := clang-test --target=arm-linux-androideabi"
require_tool "LD := ld.lld-test"

if read_tools LLVM="$test_dir/missing/" 2>/dev/null; then
	echo "missing LLVM path passed" >&2
	exit 1
fi
if read_tools LLVM=-missing 2>/dev/null; then
	echo "missing LLVM suffix passed" >&2
	exit 1
fi
ln -sf "$(command -v gcc)" "${test_dir}/clang-test"
if PATH="$test_dir:$PATH" read_tools LLVM=-test 2>/dev/null; then
	echo "non-Clang compiler passed" >&2
	exit 1
fi
if read_tools "LLVM=$llvm_bin" LLVM_IAS=invalid 2>/dev/null; then
	echo "invalid LLVM_IAS value passed" >&2
	exit 1
fi

echo "LLVM tool selection passed"
