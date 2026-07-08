.set noreorder
.set noat
.globl __start
.section text

__start:
.text
    lui     $a0, 0x8040
    lui     $a1, 0x8041
    lui     $a2, 0x8042
    addiu   $a3, $zero, 96
    or      $v1, $zero, $zero
loop1:
    beq     $v1, $a3, loop1end
    sll     $t0, $v1, 2

    sll     $t2, $v1, 9
    addu    $t0, $a0, $t0
    addu    $t2, $a1, $t2
    or      $t1, $zero, $zero
loop2:
    beq     $t1, $a3, loop2end
    sll     $v0, $t1, 9

    lw      $t7, 0($t0)
    addu    $v0, $a2, $v0
    or      $t4, $t2, $zero
    or      $t3, $zero, $zero
loop3:
    beq     $t3, $a3, loop3end
    addiu   $t3, $t3, 1

    lw      $t5, 0($t4)
    lw      $t6, 0($v0)
    mul     $t5, $t7, $t5
    addiu   $v0, $v0, 4
    addiu   $t4, $t4, 4
    addu    $t5, $t6, $t5
    beq     $zero, $zero, loop3
    sw      $t5, -4($v0)

loop3end:
    addiu   $t1, $t1, 1
    beq     $zero, $zero, loop2
    addiu   $t0, $t0, 512

loop2end:
    beq     $zero, $zero, loop1
    addiu   $v1, $v1, 1

loop1end:
halt:
    jr      $ra
    sll     $zero, $zero, 0
