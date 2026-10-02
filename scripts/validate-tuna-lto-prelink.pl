#!/usr/bin/env perl
# SPDX-License-Identifier: GPL-2.0
# Check the native ARM object before modpost and the final strict link.

use strict;
use warnings;

(@ARGV == 2 || @ARGV == 3 && $ARGV[2] eq '--mcount')
	or die "usage: $0 READELF VMLINUX_OBJECT [--mcount]\n";
my ($readelf, $object, $mcount_required) = @ARGV;

sub readelf_output {
	my (@arguments) = @_;
	open my $pipe, '-|', $readelf, @arguments, $object
		or die "cannot run $readelf: $!\n";
	local $/;
	my $output = <$pipe>;
	close $pipe or die "$readelf failed for $object\n";
	return $output;
}

my $header = readelf_output('-h');
$header =~ /^\s*Class:\s+ELF32\s*$/m or die "$object: expected ELF32\n";
$header =~ /^\s*Data:\s+2's complement, little endian\s*$/m
	or die "$object: expected little-endian ELF\n";
$header =~ /^\s*Type:\s+REL\s/m or die "$object: expected relocatable ELF\n";
$header =~ /^\s*Machine:\s+ARM\s*$/m or die "$object: expected ARM ELF\n";
my ($elf_flags) = $header =~ /^\s*Flags:\s+(0x[0-9a-fA-F]+)/m;
defined($elf_flags) && (hex($elf_flags) & 0xff000000) == 0x05000000
	or die "$object: expected ARM EABI5 ELF\n";

my $table = readelf_output('-SW');
my ($count) = $table =~ /^There are (\d+) section headers/m;
defined $count or die "$object: missing section count\n";
my @sections = ({ name => '', type => 'NULL' });
my %by_name;
for my $line (split /\n/, $table) {
	$line =~ s/SYMTAB SECTION INDICES/SYMTAB_SHNDX/;
	next unless $line =~ /^\s*\[\s*(\d+)\]\s+(\S+)\s+(\S+)\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+([A-Z]*)\s+(\d+)\s+(\d+)\s+(\d+)\s*$/;
	my ($index, $name, $type, $size, $entry_size, $flags, $link, $info,
		$alignment) = ($1, $2, $3, $6, $7, $8, $9, $10, $11);
	$index == @sections or die "$object: section index gap at $index\n";
	exists $by_name{$name} and die "$object: duplicate section $name\n";
	my $section = { name => $name, type => $type, flags => $flags,
		link => $link, info => $info, size => hex($size),
		entry_size => hex($entry_size), alignment => $alignment };
	push @sections, $section;
	$by_name{$name} = $section;
}
@sections == $count or die "$object: parsed " . scalar(@sections) .
	" of $count sections\n";

sub check_section {
	my ($section, $type, $required, $forbidden) = @_;
	my $name = $section->{name};
	$section->{type} eq $type or die "$object: $name has type $section->{type}, expected $type\n";
	$section->{flags} =~ /$_/ or die "$object: $name lacks flag $_\n"
		for split //, $required;
	$section->{flags} !~ /$_/ or die "$object: $name has forbidden flag $_\n"
		for split //, $forbidden;
}

my $initcall_count = 0;
my %unrecognized;
for my $section (@sections) {
	my ($name, $type) = @{$section}{qw(name type)};
	next if $type eq 'NULL';
	if ($type eq 'REL' || $type eq 'RELA') {
		$name =~ /^\.rela?(.+)$/ or die "$object: unexpected relocation $name\n";
		my $expected = $1;
		my $target = $sections[$section->{info}]
			or die "$object: $name has invalid relocation target\n";
		my $matches = $target->{name} eq $expected;
		if (!$matches && $expected =~ /^(\.(?:initcall(?:early|rootfs|[0-7]s?)|con_initcall|security_initcall)\.init)\.\./) {
			$matches = $target->{name} eq $1;
		}
		$matches or die "$object: $name targets $target->{name}, expected $expected\n";
		$target->{flags} =~ /A/
			or die "$object: $name targets a non-allocated section\n";
		my $symbols = $sections[$section->{link}]
			or die "$object: $name has invalid symbol table link\n";
		$symbols->{type} eq 'SYMTAB'
			or die "$object: $name does not link to SYMTAB\n";
		check_section($section, $type, '', 'AWX');
	} elsif ($name =~ /^\.ARM\.exidx(?:\.(.+))?$/) {
		my $target_name = defined($1) ? ".$1" : '.text';
		my $target = $sections[$section->{link}]
			or die "$object: $name has invalid unwind link\n";
		$target->{name} eq $target_name
			or die "$object: $name links $target->{name}, expected $target_name\n";
		check_section($section, 'ARM_EXIDX', 'AL', 'WX');
	} elsif ($name =~ /^\.(?:text|init\.text|exit\.text|ref\.text|sched\.text|head\.text|entry\.text|spinlock\.text|devinit\.text|devexit\.text|cpuinit\.text|cpuexit\.text|meminit\.text|memexit\.text)(?:\..+)?$/ ||
		 $name eq '.fixup' || $name eq '.irqentry.text' ||
		 $name eq '.exception.text') {
		check_section($section, 'PROGBITS', 'AX', 'W');
	} elsif ($name =~ /^\.(?:bss|sbss)(?:\..+)?$/) {
		check_section($section, 'NOBITS', 'WA', 'X');
	} elsif ($name =~ /^\.(?:data|sdata|init\.data|exit\.data|ref\.data|devinit\.data|devexit\.data|cpuinit\.data|cpuexit\.data|meminit\.data|memexit\.data|data\.rel\.ro)(?:\..+)?$/ ||
		 $name =~ /^\.(?:init\.setup|exitcall\.exit|arch\.info\.init|taglist\.init)$/ ||
		 $name =~ /^(?:__param|__modver|__tracepoints|__tracepoints_ptrs|_ftrace_events)$/ ||
		 $name =~ /^___(?:ksymtab|kcrctab)(?:_gpl)?\+.+$/ ||
		 $name =~ /^\.(?:initcall(?:early|rootfs|[0-7]s?)|con_initcall|security_initcall)\.init$/) {
		check_section($section, 'PROGBITS', 'WA', 'X');
		$initcall_count++ if $name =~ /initcall/;
	} elsif ($name =~ /^\.(?:rodata|init\.rodata|exit\.rodata|init\.ramfs(?:\.info)?|alt\.smp\.init|proc\.info\.init|builtin_fw|ARM\.extab)(?:\..+)?$/ ||
		 $name =~ /^(?:__ex_table|__ksymtab_strings|__ksymtab|__kcrctab|__bug_table|__tracepoints_strings)(?:[+_].+)?$/) {
		check_section($section, 'PROGBITS', 'A', 'WX');
	} elsif ($name eq '.symtab') {
		check_section($section, 'SYMTAB', '', 'AWX');
	} elsif ($name eq '.symtab_shndx') {
		check_section($section, 'SYMTAB_SHNDX', '', 'AWX');
		my $symbols = $sections[$section->{link}]
			or die "$object: extended symbol indices lack a symbol table\n";
		$symbols->{name} eq '.symtab'
			or die "$object: extended symbol indices link to $symbols->{name}\n";
	} elsif ($name eq '__mcount_loc') {
		check_section($section, 'PROGBITS', 'A', 'WX');
		$section->{entry_size} == 4 && $section->{alignment} >= 4 &&
		$section->{size} > 0 && $section->{size} % 4 == 0
			or die "$object: invalid __mcount_loc layout\n";
	} elsif ($name =~ /^\.(?:strtab|shstrtab)$/) {
		check_section($section, 'STRTAB', '', 'AWX');
	} elsif ($name eq '.ARM.attributes') {
		check_section($section, 'ARM_ATTRIBUTES', '', 'AWX');
	} elsif ($name eq '.llvm_addrsig') {
		check_section($section, 'LLVM_ADDRSIG', '', 'AWX');
	} elsif ($name =~ /^\.(?:debug|zdebug|comment|note\.GNU-stack)/) {
		$section->{flags} !~ /[AWX]/
			or die "$object: metadata section $name is allocated or executable\n";
	} else {
		$unrecognized{$name}++;
	}
}

if (%unrecognized) {
	my @names = sort keys %unrecognized;
	die "$object: unrecognized sections: " . join(', ', @names[0 ..
		($#names < 49 ? $#names : 49)]) .
		(@names > 50 ? ' ... (' . scalar(@names) . ' total)' : '') . "\n";
}

$initcall_count or die "$object: missing ordered initcall output\n";
exists $by_name{'.symtab'} or die "$object: missing symbol table\n";
open my $symbol_pipe, '-|', $readelf, '-sW', $object
	or die "cannot read symbols in $object: $!\n";
my $unresolved_crc = 0;
my %symbol_section;
while (my $line = <$symbol_pipe>) {
	if ($mcount_required && $line =~
	    /^\s*(\d+):\s+[0-9a-fA-F]+\s+\d+\s+\S+\s+\S+\s+\S+\s+(\S+)/) {
		$symbol_section{$1} = $2;
	}
	next if index($line, '__crc_') < 0;
	$unresolved_crc = 1 if $line =~ /[ \t]UND[ \t]+__crc_\S+/;
}
close $symbol_pipe or die "$readelf failed to read symbols in $object\n";
$unresolved_crc and die "$object: unresolved export CRC\n";

if ($mcount_required) {
	my $locations = $by_name{'__mcount_loc'}
		or die "$object: missing __mcount_loc\n";
	my $relocations = $by_name{'.rel__mcount_loc'}
		or die "$object: missing __mcount_loc relocations\n";
	$relocations->{size} == $locations->{size} * 2 &&
		$relocations->{entry_size} == 8
		or die "$object: __mcount_loc relocation count mismatch\n";
	open my $relocation_pipe, '-|', $readelf, '-rW', $object
		or die "cannot read relocations in $object: $!\n";
	my ($call_count, $location_count, $current_section) = (0, 0, '');
	while (my $line = <$relocation_pipe>) {
		if ($line =~ /^Relocation section '([^']+)'/) {
			$current_section = $1;
			next;
		}
		my ($offset, $info, $type) = $line =~
			/^[ \t]*([0-9a-fA-F]+)[ \t]+([0-9a-fA-F]+)[ \t]+(R_ARM_\S+)/;
		next unless defined $type;
		if ($current_section eq '.rel__mcount_loc') {
			$type eq 'R_ARM_ABS32' && hex($offset) == $location_count * 4
				or die "$object: invalid __mcount_loc relocation at $offset\n";
			# Each entry is relative to a symbol in the traced text
			# section; an absolute or undefined base leaves the call
			# address unrelocated in the final image.
			my $base = $symbol_section{hex($info) >> 8};
			defined($base) && $base =~ /^\d+$/ &&
				$sections[$base] && $sections[$base]{flags} =~ /X/
				or die "$object: __mcount_loc entry at $offset is not based in an executable section\n";
			$location_count++;
		} elsif ($current_section =~
			/^\.rel(?:\.text(?:\..+)?|\.(?:init|ref|sched|spinlock|irqentry|kprobes)\.text)$/ &&
			$type =~ /^R_ARM_(?:CALL|PC24|THM_CALL|THM_PC22)$/ &&
			$line =~ /[ \t](?:mcount|__gnu_mcount_nc)[ \t]*$/) {
			$call_count++;
		}
	}
	close $relocation_pipe
		or die "$readelf failed to read relocations in $object\n";
	$location_count == $locations->{size} / 4 &&
		$call_count == $location_count
		or die "$object: $call_count traced calls but $location_count __mcount_loc entries\n";
}
