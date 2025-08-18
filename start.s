.globl _start

.text

_start:
    li sp, (0x00030000 - 16)        # PC = 0x0000
    la a0, vec_src1                 # PC = 0x0004
    la a1, vec_src2                 # PC = 0x0008
    la a2, vec_dst                  # PC = 0x000C
    vle32.v v1, (a0)                # PC = 0x0010
    vle32.v v2, (a1)                # PC = 0x0014
    vadd.vv v3, v1, v2              # PC = 0x0018
    vse32.v v3, (a2)                # PC = 0x001C
    # call main
    call halt                       # PC = 0x0020
    j _start                        # PC = 0x0024

# Data section for vectors
.data
.align 4
vec_src1:
    .word 1, 2, 3, 4
vec_src2:
    .word 10, 20, 30, 40
vec_dst:
    .space 16  # Reserve space for 4 words (vector result)
    