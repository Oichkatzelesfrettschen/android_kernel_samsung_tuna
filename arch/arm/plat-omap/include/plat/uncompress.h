/*
 * arch/arm/plat-omap/include/mach/uncompress.h
 *
 * Serial port stubs for kernel decompress status messages
 *
 * Initially based on:
 * linux-2.4.15-rmk1-dsplinux1.6/arch/arm/plat-omap/include/mach1510/uncompress.h
 * Copyright (C) 2000 RidgeRun, Inc.
 * Author: Greg Lonnon <glonnon@ridgerun.com>
 *
 * Rewritten by:
 * Author: <source@mvista.com>
 * 2004 (c) MontaVista Software, Inc.
 *
 * This file is licensed under the terms of the GNU General Public License
 * version 2. This program is licensed "as is" without any warranty of any
 * kind, whether express or implied.
 */

#include <linux/types.h>
#include <linux/serial_reg.h>

#include <asm/memory.h>
#include <asm/mach-types.h>

#include <plat/serial.h>

#define MDR1_MODE_MASK			0x07

volatile u8 *uart_base;
int uart_shift;

/*
 * Store the DEBUG_LL uart number into memory.
 * See also debug-macro.S, and serial.c for related code.
 */
static void set_omap_uart_info(unsigned char port)
{
	*(volatile u32 *)OMAP_UART_INFO = port;
}

static void putc(int c)
{
	if (!uart_base)
		return;

	/* Check for UART 16x mode */
	if ((uart_base[UART_OMAP_MDR1 << uart_shift] & MDR1_MODE_MASK) != 0)
		return;

	while (!(uart_base[UART_LSR << uart_shift] & UART_LSR_THRE))
		barrier();
	uart_base[UART_TX << uart_shift] = c;
}

static inline void flush(void)
{
}

/*
 * Macros to configure UART1 and debug UART
 */
#define _DEBUG_LL_ENTRY(mach, dbg_uart, dbg_shft, dbg_id)		\
	if (machine_is_##mach()) {					\
		uart_base = (volatile u8 *)(dbg_uart);			\
		uart_shift = (dbg_shft);				\
		port = (dbg_id);					\
		set_omap_uart_info(port);				\
		break;							\
	}

#define DEBUG_LL_OMAP7XX(p, mach)					\
	_DEBUG_LL_ENTRY(mach, OMAP1_UART##p##_BASE, OMAP7XX_PORT_SHIFT,	\
		OMAP1UART##p)

#define DEBUG_LL_OMAP1(p, mach)						\
	_DEBUG_LL_ENTRY(mach, OMAP1_UART##p##_BASE, OMAP_PORT_SHIFT,	\
		OMAP1UART##p)

#define DEBUG_LL_OMAP2(p, mach)						\
	_DEBUG_LL_ENTRY(mach, OMAP2_UART##p##_BASE, OMAP_PORT_SHIFT,	\
		OMAP2UART##p)

#define DEBUG_LL_OMAP3(p, mach)						\
	_DEBUG_LL_ENTRY(mach, OMAP3_UART##p##_BASE, OMAP_PORT_SHIFT,	\
		OMAP3UART##p)

#define DEBUG_LL_OMAP4(p, mach)						\
	_DEBUG_LL_ENTRY(mach, OMAP4_UART##p##_BASE, OMAP_PORT_SHIFT,	\
		OMAP4UART##p)

/* Zoom2/3 shift is different for UART1 and external port */
#define DEBUG_LL_ZOOM(mach)						\
	_DEBUG_LL_ENTRY(mach, ZOOM_UART_BASE, ZOOM_PORT_SHIFT, ZOOM_UART)

#define DEBUG_LL_TI816X(p, mach)					\
	_DEBUG_LL_ENTRY(mach, TI816X_UART##p##_BASE, OMAP_PORT_SHIFT,	\
		TI816XUART##p)

#ifdef CONFIG_OMAP_WATCHDOG_BOOT_COVERAGE
/* OMAP4430 WDT2 (wd_timer2) and its CM_WKUP clock control register. */
#define OMAP4_WDT2_BASE			0x4a314000
#define OMAP4_WDT2_WCLR			(OMAP4_WDT2_BASE + 0x24)
#define OMAP4_WDT2_WLDR			(OMAP4_WDT2_BASE + 0x2c)
#define OMAP4_WDT2_WTGR			(OMAP4_WDT2_BASE + 0x30)
#define OMAP4_WDT2_WWPS			(OMAP4_WDT2_BASE + 0x34)
#define OMAP4_WDT2_WSPR			(OMAP4_WDT2_BASE + 0x48)
#define OMAP4_CM_WKUP_WDT2_CLKCTRL	0x4a307830

#define omap4_wdt2_reg(addr)		(*(volatile u32 *)(addr))

/* Posted-write polls are bounded so an unclocked module cannot stall boot. */
static inline void omap4_wdt2_wait(u32 pending)
{
	u32 n = 0x100000;

	while ((omap4_wdt2_reg(OMAP4_WDT2_WWPS) & pending) && --n)
		;
}

static inline void omap4_wdt2_write(u32 reg, u32 val, u32 pending)
{
	omap4_wdt2_wait(pending);
	omap4_wdt2_reg(reg) = val;
	omap4_wdt2_wait(pending);
}

/*
 * Start WDT2 before the kernel runs. The counter ticks at 32768 Hz with the
 * prescaler at 1, and a WTGR value change reloads it from WLDR; two
 * distinct trigger writes guarantee one change whatever WTGR held.
 */
static inline void omap4_boot_watchdog_arm(void)
{
	u32 n = 0x100000;

	omap4_wdt2_reg(OMAP4_CM_WKUP_WDT2_CLKCTRL) =
		(omap4_wdt2_reg(OMAP4_CM_WKUP_WDT2_CLKCTRL) & ~0x3) | 0x2;
	while ((omap4_wdt2_reg(OMAP4_CM_WKUP_WDT2_CLKCTRL) & (0x3 << 16)) && --n)
		;

	omap4_wdt2_write(OMAP4_WDT2_WCLR, 1 << 5, 1 << 0);
	omap4_wdt2_write(OMAP4_WDT2_WLDR,
			 0xffffffff - CONFIG_OMAP_WATCHDOG_BOOT_MARGIN * 32768 + 1,
			 1 << 2);
	omap4_wdt2_write(OMAP4_WDT2_WTGR, 0x5a5a5a5a, 1 << 3);
	omap4_wdt2_write(OMAP4_WDT2_WTGR, 0xa5a5a5a5, 1 << 3);
	omap4_wdt2_write(OMAP4_WDT2_WSPR, 0xbbbb, 1 << 4);
	omap4_wdt2_write(OMAP4_WDT2_WSPR, 0x4444, 1 << 4);
}
#else
static inline void omap4_boot_watchdog_arm(void)
{
}
#endif

static inline void __arch_decomp_setup(unsigned long arch_id)
{
	int port = 0;

	omap4_boot_watchdog_arm();

	/*
	 * Initialize the port based on the machine ID from the bootloader.
	 * Note that we're using macros here instead of switch statement
	 * as machine_is functions are optimized out for the boards that
	 * are not selected.
	 */
	do {
		/* omap7xx/8xx based boards using UART1 with shift 0 */
		DEBUG_LL_OMAP7XX(1, herald);
		DEBUG_LL_OMAP7XX(1, omap_perseus2);

		/* omap15xx/16xx based boards using UART1 */
		DEBUG_LL_OMAP1(1, ams_delta);
		DEBUG_LL_OMAP1(1, nokia770);
		DEBUG_LL_OMAP1(1, omap_h2);
		DEBUG_LL_OMAP1(1, omap_h3);
		DEBUG_LL_OMAP1(1, omap_innovator);
		DEBUG_LL_OMAP1(1, omap_osk);
		DEBUG_LL_OMAP1(1, omap_palmte);
		DEBUG_LL_OMAP1(1, omap_palmz71);

		/* omap15xx/16xx based boards using UART2 */
		DEBUG_LL_OMAP1(2, omap_palmtt);

		/* omap15xx/16xx based boards using UART3 */
		DEBUG_LL_OMAP1(3, sx1);

		/* omap2 based boards using UART1 */
		DEBUG_LL_OMAP2(1, omap_2430sdp);
		DEBUG_LL_OMAP2(1, omap_apollon);
		DEBUG_LL_OMAP2(1, omap_h4);

		/* omap2 based boards using UART3 */
		DEBUG_LL_OMAP2(3, nokia_n800);
		DEBUG_LL_OMAP2(3, nokia_n810);
		DEBUG_LL_OMAP2(3, nokia_n810_wimax);

		/* omap3 based boards using UART1 */
		DEBUG_LL_OMAP2(1, omap3evm);
		DEBUG_LL_OMAP3(1, omap_3430sdp);
		DEBUG_LL_OMAP3(1, omap_3630sdp);
		DEBUG_LL_OMAP3(1, omap3530_lv_som);
		DEBUG_LL_OMAP3(1, omap3_torpedo);

		/* omap3 based boards using UART3 */
		DEBUG_LL_OMAP3(3, cm_t35);
		DEBUG_LL_OMAP3(3, cm_t3517);
		DEBUG_LL_OMAP3(3, craneboard);
		DEBUG_LL_OMAP3(3, devkit8000);
		DEBUG_LL_OMAP3(3, igep0020);
		DEBUG_LL_OMAP3(3, igep0030);
		DEBUG_LL_OMAP3(3, nokia_rm680);
		DEBUG_LL_OMAP3(3, nokia_rx51);
		DEBUG_LL_OMAP3(3, omap3517evm);
		DEBUG_LL_OMAP3(3, omap3_beagle);
		DEBUG_LL_OMAP3(3, omap3_pandora);
		DEBUG_LL_OMAP3(3, omap_ldp);
		DEBUG_LL_OMAP3(3, overo);
		DEBUG_LL_OMAP3(3, touchbook);

		/* omap4 based boards using UART3 */
		DEBUG_LL_OMAP4(3, omap_4430sdp);
		DEBUG_LL_OMAP4(3, omap4_panda);
		DEBUG_LL_OMAP4(3, omap_tabletblaze);
		DEBUG_LL_OMAP4(3, tuna);

		/* omap4 based boards using UART4 */
		DEBUG_LL_OMAP4(4, omap4_espresso)

		/* zoom2/3 external uart */
		DEBUG_LL_ZOOM(omap_zoom2);
		DEBUG_LL_ZOOM(omap_zoom3);

		/* TI8168 base boards using UART3 */
		DEBUG_LL_TI816X(3, ti8168evm);

	} while (0);
}

#define arch_decomp_setup()	__arch_decomp_setup(arch_id)

/*
 * nothing to do
 */
#define arch_decomp_wdog()
