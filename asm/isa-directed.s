.set noreorder
.set noat
.globl __start
.section text

__start:
.text
    xor   $s0, $s0, $s0       # fail count
    lui   $s1, 0x8040
    ori   $s1, $s1, 0x0100    # result base = 0x80400100

    ori   $t0, $zero, 0x00f0
    ori   $t1, $zero, 0x0f00
    or    $t2, $t0, $t1
    xori  $t3, $t2, 0x0ff0
    beq   $t3, $zero, logic_ok
    ori   $zero, $zero, 0
    addiu $s0, $s0, 1
logic_ok:
    andi  $t4, $t2, 0x00f0
    bne   $t4, $t0, logic_fail2
    ori   $zero, $zero, 0
    and   $t5, $t2, $t1
    beq   $t5, $t1, logic_done
    ori   $zero, $zero, 0
logic_fail2:
    addiu $s0, $s0, 1
logic_done:

    ori   $t0, $zero, 7
    ori   $t1, $zero, 5
    add   $t2, $t0, $t1
    addi  $t2, $t2, -2
    sub   $t2, $t2, $t1
    addiu $t2, $t2, 1
    ori   $t3, $zero, 6
    beq   $t2, $t3, arith_ok
    ori   $zero, $zero, 0
    addiu $s0, $s0, 1
arith_ok:
    slt   $t4, $t1, $t0
    bne   $t4, $zero, slt_ok
    ori   $zero, $zero, 0
    addiu $s0, $s0, 1
slt_ok:
    addiu $t5, $zero, -3
    ori   $t6, $zero, 7
    mul   $t7, $t5, $t6
    addiu $t8, $zero, -21
    beq   $t7, $t8, mul_ok
    ori   $zero, $zero, 0
    addiu $s0, $s0, 1
mul_ok:

    ori   $t0, $zero, 1
    sll   $t1, $t0, 5
    srl   $t2, $t1, 2
    ori   $t3, $zero, 8
    bne   $t2, $t3, shift_fail
    ori   $zero, $zero, 0
    addiu $t4, $zero, -16
    sra   $t5, $t4, 2
    addiu $t6, $zero, -4
    bne   $t5, $t6, shift_fail
    ori   $zero, $zero, 0
    ori   $t7, $zero, 3
    sllv  $t8, $t0, $t7
    srlv  $t9, $t8, $t7
    bne   $t9, $t0, shift_fail
    ori   $zero, $zero, 0
    srav  $t5, $t4, $t7
    addiu $t6, $zero, -2
    beq   $t5, $t6, shift_ok
    ori   $zero, $zero, 0
shift_fail:
    addiu $s0, $s0, 1
shift_ok:

    ori   $t0, $zero, 0x7b
    sb    $t0, 4($s1)
    lb    $t1, 4($s1)
    ori   $t2, $zero, 0x007b
    beq   $t1, $t2, lb_positive_ok
    ori   $zero, $zero, 0
    addiu $s0, $s0, 1
lb_positive_ok:
    ori   $t0, $zero, 0x80
    sb    $t0, 5($s1)
    lb    $t1, 5($s1)
    addiu $t2, $zero, -128
    bne   $t1, $t2, mem_fail
    ori   $zero, $zero, 0
    ori   $t3, $zero, 0x1234
    sw    $t3, 8($s1)
    lw    $t4, 8($s1)
    beq   $t3, $t4, mem_ok
    ori   $zero, $zero, 0
mem_fail:
    addiu $s0, $s0, 1
mem_ok:

    addiu $t0, $zero, -1
    bltz  $t0, bltz_ok
    ori   $zero, $zero, 0
    addiu $s0, $s0, 1
bltz_ok:
    bgez  $zero, bgez_ok
    ori   $zero, $zero, 0
    addiu $s0, $s0, 1
bgez_ok:
    blez  $zero, blez_ok
    ori   $zero, $zero, 0
    addiu $s0, $s0, 1
blez_ok:
    ori   $t1, $zero, 1
    bgtz  $t1, bgtz_ok
    ori   $zero, $zero, 0
    addiu $s0, $s0, 1
bgtz_ok:

    jal   jal_target
    ori   $t0, $zero, 0x11
after_jal:
    ori   $t2, $zero, 0x33
    bne   $t1, $t2, jump_fail
    ori   $zero, $zero, 0

    lui   $t3, %hi(jalr_target)
    ori   $t3, $t3, %lo(jalr_target)
    jalr  $ra, $t3
    ori   $t0, $zero, 0x22
after_jalr:
    ori   $t4, $zero, 0x44
    bne   $t1, $t4, jump_fail
    ori   $zero, $zero, 0

    j     jump_ok
    ori   $zero, $zero, 0
jump_fail:
    addiu $s0, $s0, 1
    j     jump_ok
    ori   $zero, $zero, 0

jal_target:
    ori   $t1, $zero, 0x33
    jr    $ra
    ori   $zero, $zero, 0

jalr_target:
    ori   $t1, $zero, 0x44
    jr    $ra
    ori   $zero, $zero, 0

jump_ok:
    sw    $s0, 0($s1)

halt:
    j     halt
    ori   $zero, $zero, 0
