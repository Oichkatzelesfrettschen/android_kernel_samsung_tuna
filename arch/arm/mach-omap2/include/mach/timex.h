/*
 * arch/arm/mach-omap2/include/mach/timex.h
 */

#include <plat/timex.h>

#ifdef CONFIG_ARCH_OMAP4
unsigned long omap4_get_cycles(void);
#endif
