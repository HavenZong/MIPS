.set noreorder
.set noat
.globl __start
.globl _start
.section text

__start:
_start:
.text
    or    $s1, $ra, $zero
    xor   $v0, $v0, $v0
    lui   $s0, 0x8040

    ori   $t0, $zero, 0x00f0
    ori   $t1, $zero, 0x0f00
    or    $t2, $t0, $t1
    andi  $t3, $t2, 0x00f0
    bne   $t3, $t0, fail_logic
    ori   $zero, $zero, 0
    and   $t4, $t2, $t1
    xor   $t5, $t2, $t0
    xori  $t6, $t5, 0x0f00
    bne   $t6, $zero, fail_logic
    ori   $zero, $zero, 0
    beq   $t4, $t1, logic_ok
    ori   $zero, $zero, 0
fail_logic:
    addiu $v0, $v0, 1

logic_ok:
    ori   $t0, $zero, 1
    sll   $t1, $t0, 5
    srl   $t2, $t1, 2
    ori   $t3, $zero, 8
    beq   $t2, $t3, shift_ok
    ori   $zero, $zero, 0
    addiu $v0, $v0, 1

shift_ok:
    addiu $t0, $zero, 5
    addiu $t1, $zero, 7
    addu  $t2, $t0, $t1
    addiu $t2, $t2, -2
    ori   $t3, $zero, 10
    bne   $t2, $t3, fail_arith
    ori   $zero, $zero, 0
    bgtz  $t2, arith_ok
    ori   $zero, $zero, 0
fail_arith:
    addiu $v0, $v0, 1

arith_ok:
    ori   $t0, $zero, 0x007b
    sb    $t0, 4($s0)
    lb    $t1, 4($s0)
    bne   $t1, $t0, fail_mem
    ori   $zero, $zero, 0
    ori   $t2, $zero, 0x1234
    sw    $t2, 8($s0)
    lw    $t3, 8($s0)
    beq   $t2, $t3, mem_ok
    ori   $zero, $zero, 0
fail_mem:
    addiu $v0, $v0, 1

mem_ok:
    jal   mark_jal_ok
    ori   $zero, $zero, 0
after_jal:
    ori   $t5, $zero, 0x55
    bne   $t4, $t5, fail_jump
    ori   $zero, $zero, 0
    j     done
    ori   $zero, $zero, 0

fail_jump:
    addiu $v0, $v0, 1
    j     done
    ori   $zero, $zero, 0

mark_jal_ok:
    ori   $t4, $zero, 0x55
    jr    $ra
    ori   $zero, $zero, 0

done:
    sw    $v0, 0($s0)
    jr    $s1
    ori   $zero, $zero, 0
