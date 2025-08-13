.section .data
    .align 2
data:
    .rept 512
    .word 0
    .endr

    .section .text
    .globl main
main:
    # Initialize loop counter i = 0
    li t0, 0                # t0 = i

    # Load base address of data[] into t1
    la t1, data             # t1 = &data[0]

loop:
    # Check: if i >= 512, exit
    li t2, 512
    bge t0, t2, done

    # Load data[i] into t3
    slli t4, t0, 2          # t4 = i * 4 (word offset)
    add t5, t1, t4          # t5 = &data[i]
    lw t3, 0(t5)            # t3 = data[i]

    # Prevent compiler from optimizing away (nop here acts as barrier)
    nop

    # i++
    addi t0, t0, 1
    j loop

done:
    li a0, 0                # return 0
    call halt
    ret