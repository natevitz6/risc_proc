.section .data
    .align 2
data:
    .rept 1024              # 1024 words = 4 KB
    .word 0
    .endr

    .section .text
    .globl _start
_start:
    la s0, data             # s0 = base address of data
    li s1, 4                # word size (4 bytes)
    li s2, 5                # stride in words
    li s3, 204              # max stride accesses (1024 / 5)
    li s4, 4                # number of passes
    li s5, 0                # pass counter

outer_loop:
    li t0, 0                # i = 0 (stride index)

inner_loop:
    bge t0, s3, next_pass   # if i >= 204, go to next pass

    # Calculate byte offset = i * stride * 4
    # i * 5 = (i << 2) + i
    slli t1, t0, 2          # t1 = i * 4
    add t1, t1, t0          # t1 = i * 5 (word offset)
    slli t1, t1, 2          # t1 = i * 5 * 4 = byte offset

    add t2, s0, t1          # t2 = &data[i * stride]
    lw t3, 0(t2)            # load data[i * stride]

    addi t0, t0, 1          # i++
    j inner_loop

next_pass:
    addi s5, s5, 1          # pass++
    blt s5, s4, outer_loop  # if pass < 4, repeat

done:
    li a0, 0
    call halt
    ret

