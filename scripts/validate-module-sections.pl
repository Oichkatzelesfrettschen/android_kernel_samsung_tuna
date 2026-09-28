#!/usr/bin/env perl
use strict;
use warnings;

@ARGV >= 2 && @ARGV <= 4
	or die "usage: $0 READELF MODULE [--modversions] [--prelink]\n";
my ($readelf, $module, @options) = @ARGV;
my %options;
for my $option (@options) {
	$option eq '--modversions' || $option eq '--prelink'
		or die "unknown option: $option\n";
	$options{$option}++ and die "duplicate option: $option\n";
}

sub readelf_output {
	my (@arguments) = @_;
	open(my $pipe, '-|', $readelf, @arguments, $module)
		or die "cannot run $readelf: $!\n";
	local $/;
	my $output = <$pipe>;
	close($pipe) or die "$readelf failed for $module\n";
	return $output;
}

my $header = readelf_output('-h');
$header =~ /^\s*Class:\s+ELF32\s*$/m or die "$module: expected ELF32\n";
$header =~ /^\s*Data:\s+2's complement, little endian\s*$/m
	or die "$module: expected little-endian ELF\n";
$header =~ /^\s*Type:\s+REL\s/m or die "$module: expected relocatable ELF\n";
$header =~ /^\s*Machine:\s+ARM\s*$/m or die "$module: expected ARM ELF\n";
my ($elf_flags) = $header =~ /^\s*Flags:\s+(0x[0-9a-fA-F]+)/m;
defined($elf_flags) && (hex($elf_flags) & 0xff000000) == 0x05000000
	or die "$module: expected ARM EABI5 ELF\n";

my $section_table = readelf_output('-SW');
my ($section_count) = $section_table =~ /^There are (\d+) section headers/m;
defined $section_count or die "$module: missing section count\n";
my (@sections, %by_name);
push @sections, { name => '', type => 'NULL' };
for my $line (split /\n/, $section_table) {
	next unless $line =~ /^\s*\[\s*(\d+)\]\s+(\S+)\s+(\S+)\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+([A-Z]*)\s+(\d+)\s+(\d+)\s+(\d+)\s*$/;
	my ($index, $name, $type, $address, $offset, $size, $entry_size,
	    $flags, $link, $info, $alignment) =
	    ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11);
	$index == @sections or die "$module: section index gap at $index\n";
	exists $by_name{$name} and die "$module: duplicate section $name\n";
	my $section = { name => $name, type => $type, flags => $flags,
		link => $link, info => $info, size => hex($size),
		entry_size => hex($entry_size), alignment => $alignment };
	push @sections, $section;
	$by_name{$name} = $section;
}
@sections > 1 or die "$module: unreadable section table\n";
@sections == $section_count
	or die "$module: parsed " . scalar(@sections) . " of $section_count sections\n";

sub check_section {
	my ($section, $expected_type, $required_flags, $forbidden_flags) = @_;
	my $name = $section->{name};
	$section->{type} eq $expected_type
		or die "$module: $name has type $section->{type}, expected $expected_type\n";
	$section->{flags} =~ /$_/ or die "$module: $name lacks flag $_\n"
		for split //, $required_flags;
	$section->{flags} !~ /$_/ or die "$module: $name has forbidden flag $_\n"
		for split //, $forbidden_flags;
}

sub linked_output_section {
	my ($name) = @_;
	return $name if $options{'--prelink'};
	for my $output (qw(.ARM.exidx.devinit.text .ARM.exidx.devexit.text
		.ARM.exidx.init.text .ARM.exidx.exit.text .ARM.exidx
		.devinit.text .devexit.text .init.text .exit.text .text
		.data..percpu .rodata .data .bss)) {
		return $name if $name eq $output;
		return $output if $name =~ /^\Q$output\E\..+/;
	}
	return $name;
}

for my $section (@sections) {
	my ($name, $type) = @{$section}{qw(name type)};
	next if $type eq 'NULL';
	if (!$options{'--prelink'} && $section->{flags} =~ /A/ &&
	    linked_output_section($name) ne $name) {
		die "$module: unmerged final section $name\n";
	}
	if ($type eq 'REL' || $type eq 'RELA') {
		$name =~ /^\.rela?(.+)$/ or die "$module: unexpected relocation $name\n";
		my $target_name = $1;
		my $target = $sections[$section->{info}]
			or die "$module: $name has invalid relocation target\n";
		my $expected_target = linked_output_section($target_name);
		my $matches = $target->{name} eq $expected_target;
		if (!$matches && $target_name =~ /^___((?:ksymtab|kcrctab)(?:_unused_gpl|_gpl_future|_unused|_gpl)?)\+[^+]+$/) {
			$matches = $target->{name} eq "__$1";
		}
		$matches or die "$module: $name targets $target->{name}, expected $expected_target\n";
		$target->{flags} =~ /A/
			or die "$module: $name targets a non-allocated section\n";
		my $symbol_table = $sections[$section->{link}]
			or die "$module: $name has invalid symbol table link\n";
		$symbol_table->{type} eq 'SYMTAB'
			or die "$module: $name does not link to SYMTAB\n";
		check_section($section, $type, '', 'AWX');
	} elsif ($name =~ /^\.ARM\.exidx(?:\.(.+))?$/) {
		my $text_name = defined($1) ? ".$1" : '.text';
		my $text_section = $sections[$section->{link}]
			or die "$module: $name has invalid unwind link\n";
		$text_section->{name} eq $text_name
			or die "$module: $name links $text_section->{name}, expected $text_name\n";
		check_section($section, 'ARM_EXIDX', 'AL', 'WX');
	} elsif ($name =~ /^\.(?:text|init\.text|exit\.text|ref\.text|devinit\.text|devexit\.text|cpuinit\.text|cpuexit\.text|meminit\.text|memexit\.text)(?:\..+)?$/) {
		check_section($section, 'PROGBITS', 'AX', 'W');
	} elsif ($name =~ /^\.(?:data|init\.data|exit\.data|ref\.data|devinit\.data|devexit\.data|cpuinit\.data|cpuexit\.data|meminit\.data|memexit\.data|sdata|bss|sbss)(?:\..+)?$/) {
		check_section($section, $name =~ /^\.(?:s?bss)(?:\.|$)/ ? 'NOBITS' : 'PROGBITS', 'WA', 'X');
	} elsif ($name eq '.gnu.linkonce.this_module') {
		check_section($section, 'PROGBITS', 'WA', 'X');
	} elsif ($name eq '__mcount_loc') {
		check_section($section, 'PROGBITS', 'A', 'WX');
		# The module loader counts pointers from sh_size; GNU ld leaves sh_entsize zero.
		($section->{entry_size} == 0 || $section->{entry_size} == 4) &&
		$section->{alignment} >= 4 &&
		$section->{size} > 0 && $section->{size} % 4 == 0
			or die "$module: invalid __mcount_loc entry layout\n";
	} elsif ($name eq '__trace_printk_fmt') {
		check_section($section, 'PROGBITS', 'WA', 'X');
		$section->{size} > 0 && $section->{size} % 4 == 0 &&
		$section->{alignment} >= 4
			or die "$module: invalid trace_printk pointer layout\n";
	} elsif ($name =~ /^(?:\.rodata|\.init\.rodata|\.exit\.rodata|\.ARM\.extab|\.modinfo|__versions|__param|__ksymtab\w*|__kcrctab\w*|__bug_table)(?:\..+)?$/ ||
		 $options{'--prelink'} && $name =~ /^___(?:ksymtab|kcrctab)(?:_gpl)?\+.+$/) {
		check_section($section, 'PROGBITS', 'A', 'WX');
	} elsif ($name eq '.symtab') {
		check_section($section, 'SYMTAB', '', 'AWX');
	} elsif ($name =~ /^\.(?:strtab|shstrtab)$/) {
		check_section($section, 'STRTAB', '', 'AWX');
	} elsif ($name eq '.ARM.attributes') {
		check_section($section, 'ARM_ATTRIBUTES', '', 'AWX');
	} elsif ($name eq '.llvm_addrsig') {
		check_section($section, 'LLVM_ADDRSIG', 'E', 'AWX');
	} elsif ($name eq '.note.gnu.build-id') {
		check_section($section, 'NOTE', 'A', 'WX');
	} elsif ($name =~ /^\.(?:debug|zdebug|comment|note\.GNU-stack)/) {
		$section->{flags} !~ /[AWX]/
			or die "$module: metadata section $name is allocated or executable\n";
	} else {
		die "$module: unrecognized section $name\n";
	}
}

for my $required ($options{'--prelink'} ? ('.modinfo', '.symtab') :
	('.modinfo', '.gnu.linkonce.this_module', '.symtab')) {
	exists $by_name{$required} && $by_name{$required}->{size}
		or die "$module: missing or empty $required\n";
}
if ($options{'--modversions'} && !$options{'--prelink'}) {
	exists $by_name{'__versions'} && $by_name{'__versions'}->{size}
		or die "$module: missing or empty __versions\n";
	$by_name{'__versions'}->{size} % 64 == 0
		or die "$module: invalid __versions entry size\n";
}
sub check_pointer_relocations {
	my ($name) = @_;
	my $pointers = $by_name{$name} or return;
	my $relocation_name = ".rel$name";
	my $relocations = $by_name{$relocation_name}
		or die "$module: missing $name relocations\n";
	$relocations->{size} == $pointers->{size} * 2 &&
	$relocations->{entry_size} == 8
		or die "$module: $name relocation count mismatch\n";
	my $relocation_table = readelf_output('-rW');
	my ($block) = $relocation_table =~
		/(Relocation section '\Q$relocation_name\E'.*?)(?=\nRelocation section '|\z)/s;
	defined $block or die "$module: missing $name relocation listing\n";
	my @entries = $block =~ /^\s*[0-9a-fA-F]+\s+[0-9a-fA-F]+\s+(R_\S+)/mg;
	@entries == $pointers->{size} / 4
		or die "$module: $name relocation listing mismatch\n";
	for my $type (@entries) {
		$type eq 'R_ARM_ABS32'
			or die "$module: invalid $name relocation $type\n";
	}
}
check_pointer_relocations('__mcount_loc');
check_pointer_relocations('__trace_printk_fmt');
my $module_info = readelf_output('-p', '.modinfo');
$module_info =~ /\bvermagic=/ or die "$module: missing vermagic\n"
	unless $options{'--prelink'};
$module_info =~ /\blicense=/ or die "$module: missing license\n";
