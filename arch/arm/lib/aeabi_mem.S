#include <linux/linkage.h>

	.text

ENTRY(__aeabi_memcpy)
	b	memcpy
ENDPROC(__aeabi_memcpy)

ENTRY(__aeabi_memcpy4)
	b	memcpy
ENDPROC(__aeabi_memcpy4)

ENTRY(__aeabi_memcpy8)
	b	memcpy
ENDPROC(__aeabi_memcpy8)

ENTRY(__aeabi_memmove)
	b	memmove
ENDPROC(__aeabi_memmove)

ENTRY(__aeabi_memmove4)
	b	memmove
ENDPROC(__aeabi_memmove4)

ENTRY(__aeabi_memmove8)
	b	memmove
ENDPROC(__aeabi_memmove8)

/* The EABI passes size before fill; memset takes fill before size. */
ENTRY(__aeabi_memset)
	mov	ip, r1
	mov	r1, r2
	mov	r2, ip
	b	memset
ENDPROC(__aeabi_memset)

ENTRY(__aeabi_memset4)
	b	__aeabi_memset
ENDPROC(__aeabi_memset4)

ENTRY(__aeabi_memset8)
	b	__aeabi_memset
ENDPROC(__aeabi_memset8)

ENTRY(__aeabi_memclr)
	b	__memzero
ENDPROC(__aeabi_memclr)

ENTRY(__aeabi_memclr4)
	b	__memzero
ENDPROC(__aeabi_memclr4)

ENTRY(__aeabi_memclr8)
	b	__memzero
ENDPROC(__aeabi_memclr8)
