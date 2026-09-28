#!/bin/sh
set -eu

if [ "$#" -ne 4 ]; then
	printf 'usage: %s VALIDATOR READELF OBJCOPY MODULE\n' "$0" >&2
	exit 2
fi

validator=$1
readelf_tool=$2
objcopy_tool=$3
module=$4
temporary_directory=$(mktemp -d)
trap 'rm -r -- "$temporary_directory"' EXIT HUP INT TERM

expect_rejection()
{
	expected_diagnostic=$2
	if perl "$validator" "$readelf_tool" "$1" --modversions >"$temporary_directory/output" 2>&1; then
		printf 'validator accepted damaged module: %s\n' "$1" >&2
		exit 1
	fi
	if ! grep -F "$expected_diagnostic" "$temporary_directory/output" >/dev/null; then
		printf 'unexpected validator diagnostic for %s:\n' "$1" >&2
		cat "$temporary_directory/output" >&2
		exit 1
	fi
}

perl "$validator" "$readelf_tool" "$module" --modversions

"$objcopy_tool" --add-section .unexpected=/dev/null "$module" "$temporary_directory/unexpected.ko"
expect_rejection "$temporary_directory/unexpected.ko" 'unrecognized section .unexpected'

"$objcopy_tool" --remove-section .modinfo "$module" "$temporary_directory/no-modinfo.ko"
expect_rejection "$temporary_directory/no-modinfo.ko" 'missing or empty .modinfo'

perl -0777 -pe 's/vermagic=/vermagik=/g' \
	"$module" >"$temporary_directory/no-vermagic.ko"
expect_rejection "$temporary_directory/no-vermagic.ko" 'missing vermagic'

"$objcopy_tool" --remove-section __versions "$module" "$temporary_directory/no-versions.ko"
expect_rejection "$temporary_directory/no-versions.ko" 'missing or empty __versions'

if "$readelf_tool" -SW "$module" | grep -F '.ARM.exidx.init.text' >/dev/null; then
	"$objcopy_tool" --rename-section .ARM.exidx.init.text=.ARM.exidx.moved.text \
		"$module" "$temporary_directory/unwind-mismatch.ko"
	expect_rejection "$temporary_directory/unwind-mismatch.ko" 'expected .moved.text'
fi

# LLVM objcopy preserves the relocation name independently of sh_info.
"$objcopy_tool" --rename-section .rel.init.text=.rel.exit.text \
	"$module" "$temporary_directory/relocation-mismatch.ko"
expect_rejection "$temporary_directory/relocation-mismatch.ko" 'expected .exit.text'

printf 'module section validation fixtures passed\n'
