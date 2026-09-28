#!/bin/sh
set -eu

if test "$#" -ne 3; then
	printf 'usage: %s READELF OBJCOPY MCOUNT_OBJECT\n' "$0" >&2
	exit 2
fi

readelf_tool=$1
objcopy_tool=$2
native_object=$3
source_tree=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
validator=$source_tree/scripts/validate-tuna-lto-prelink.pl
temporary_dir=$(mktemp -d)
trap 'rm -f "$temporary_dir"/*; rmdir "$temporary_dir"' EXIT HUP INT TERM

perl "$validator" "$readelf_tool" "$native_object" --mcount

"$objcopy_tool" --remove-section .rel__mcount_loc \
	"$native_object" "$temporary_dir/missing-relocations.o"
if perl "$validator" "$readelf_tool" "$temporary_dir/missing-relocations.o" \
	--mcount > "$temporary_dir/output" 2>&1; then
	exit 1
fi
grep -Fq 'missing __mcount_loc relocations' "$temporary_dir/output"

"$objcopy_tool" --set-section-flags __mcount_loc=alloc,data \
	"$native_object" "$temporary_dir/writable-mcount.o"
if perl "$validator" "$readelf_tool" "$temporary_dir/writable-mcount.o" \
	--mcount > "$temporary_dir/output" 2>&1; then
	exit 1
fi
grep -Fq '__mcount_loc has forbidden flag W' "$temporary_dir/output"

printf 'tuna native mcount validator mutations passed\n'
