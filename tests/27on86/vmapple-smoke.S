/* SPDX-License-Identifier: GPL-2.0-or-later */

    .section .text.boot, "ax"
    .global _start

_start:
    movz    x0, #0x2001, lsl #16
    mov     w3, #0x301
    str     w3, [x0, #0x30]
    adr     x1, message

1:
    ldrb    w2, [x1], #1
    cbz     w2, 3f

2:
    ldr     w3, [x0, #0x18]
    tbnz    w3, #5, 2b
    str     w2, [x0]
    b       1b

3:
    wfi
    b       3b

message:
    .asciz  "VMAPPLE_TCG_SMOKE_OK\n"
