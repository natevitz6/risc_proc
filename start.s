#.extern main
.globl _start

.text

_start:
    li sp, (0x00030000 - 16)
    call main
    call halt
    j _start
