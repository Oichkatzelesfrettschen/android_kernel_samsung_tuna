/*
 * Common module linker script, always used when linking a module.
 * Archs are free to supply their own linker scripts.  ld will
 * combine them automatically.
 */
SECTIONS {
	/DISCARD/ : { *(.discard) }

	/* Preserve each module loader lifetime and its ARM unwind partner. */
	.text			: { *(.text .text.*) }
	.init.text		: { *(.init.text .init.text.*) }
	.exit.text		: { *(.exit.text .exit.text.*) }
	.devinit.text		: { *(.devinit.text .devinit.text.*) }
	.devexit.text		: { *(.devexit.text .devexit.text.*) }
	.ARM.exidx		: { *(.ARM.exidx .ARM.exidx.text .ARM.exidx.text.*) }
	.ARM.exidx.init.text	: { *(.ARM.exidx.init.text .ARM.exidx.init.text.*) }
	.ARM.exidx.exit.text	: { *(.ARM.exidx.exit.text .ARM.exidx.exit.text.*) }
	.ARM.exidx.devinit.text : { *(.ARM.exidx.devinit.text .ARM.exidx.devinit.text.*) }
	.ARM.exidx.devexit.text : { *(.ARM.exidx.devexit.text .ARM.exidx.devexit.text.*) }
	.ARM.extab		: { *(.ARM.extab .ARM.extab.text .ARM.extab.text.*) }
	.ARM.extab.init.text	: { *(.ARM.extab.init.text .ARM.extab.init.text.*) }
	.ARM.extab.exit.text	: { *(.ARM.extab.exit.text .ARM.extab.exit.text.*) }
	.ARM.extab.devinit.text : { *(.ARM.extab.devinit.text .ARM.extab.devinit.text.*) }
	.ARM.extab.devexit.text : { *(.ARM.extab.devexit.text .ARM.extab.devexit.text.*) }
	.rodata			: { *(.rodata .rodata.*) }
	.data..percpu		: { *(.data..percpu .data..percpu.*) }
	.devinit.data		: { *(.devinit.data) }
	.data			: { *(.data .data.*) }
	.sdata			: { *(.sdata) }
	.bss			: { *(.bss .bss.*) }
	.sbss			: { *(.sbss) }
	__param			: { *(__param) }
	.modinfo		: { *(.modinfo) }
	.gnu.linkonce.this_module : { *(.gnu.linkonce.this_module) }
	__versions		: { *(__versions) }
	__mcount_loc		: { *(__mcount_loc) }
	__ksymtab_strings	: { *(__ksymtab_strings) }
	__trace_printk_fmt	: { *(__trace_printk_fmt) }
	.note.gnu.build-id	: { *(.note.gnu.build-id) }
	.note.GNU-stack		: { *(.note.GNU-stack) }
	.ARM.attributes		: { *(.ARM.attributes) }
	.comment		: { *(.comment) }

	__ksymtab		: { *(SORT(___ksymtab+*)) }
	__ksymtab_gpl		: { *(SORT(___ksymtab_gpl+*)) }
	__ksymtab_unused	: { *(SORT(___ksymtab_unused+*)) }
	__ksymtab_unused_gpl	: { *(SORT(___ksymtab_unused_gpl+*)) }
	__ksymtab_gpl_future	: { *(SORT(___ksymtab_gpl_future+*)) }
	__kcrctab		: { *(SORT(___kcrctab+*)) }
	__kcrctab_gpl		: { *(SORT(___kcrctab_gpl+*)) }
	__kcrctab_unused	: { *(SORT(___kcrctab_unused+*)) }
	__kcrctab_unused_gpl	: { *(SORT(___kcrctab_unused_gpl+*)) }
	__kcrctab_gpl_future	: { *(SORT(___kcrctab_gpl_future+*)) }
}
