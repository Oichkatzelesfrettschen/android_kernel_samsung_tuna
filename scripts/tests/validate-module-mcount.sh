#!/bin/sh
set -eu

if test "$#" -ne 4; then
	printf 'usage: %s VALIDATOR READELF OBJCOPY MODULE\n' "$0" >&2
	exit 2
fi

validator=$1
readelf_tool=$2
objcopy_tool=$3
module=$4
temporary_dir=$(mktemp -d)
trap 'rm -f "$temporary_dir"/*; rmdir "$temporary_dir"' EXIT HUP INT TERM

"$readelf_tool" -SW "$module" | grep -F '__mcount_loc' >/dev/null
perl "$validator" "$readelf_tool" "$module" --modversions

"$objcopy_tool" --set-section-flags __mcount_loc=alloc,data \
	"$module" "$temporary_dir/writable-mcount.ko"
if perl "$validator" "$readelf_tool" "$temporary_dir/writable-mcount.ko" \
	--modversions > "$temporary_dir/output" 2>&1; then
	exit 1
fi
grep -Fq '__mcount_loc has forbidden flag W' "$temporary_dir/output"

"$objcopy_tool" --remove-section .rel__mcount_loc \
	"$module" "$temporary_dir/missing-mcount-relocs.ko"
if perl "$validator" "$readelf_tool" "$temporary_dir/missing-mcount-relocs.ko" \
	--modversions > "$temporary_dir/output" 2>&1; then
	exit 1
fi
grep -Fq 'missing __mcount_loc relocations' "$temporary_dir/output"

printf 'module mcount section mutations passed\n'
