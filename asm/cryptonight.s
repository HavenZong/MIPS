.set noreorder
.set noat
.globl __start
.section text

__start:
.text
    lui     $a0, 0x8040
    lui     $a1, 0xdead
    ori     $a1, $a1, 0xbeef
    lui     $a2, 0xface
    ori     $a2, $a2, 0xb00c
    lui     $a3, 0x0010
    or      $v1, $zero, $a0
    or      $v0, $zero, $zero
    lui     $t0, 0x0008
clear_loop:
    sw      $v0, 0($v1)
    addiu   $v0, $v0, 1
    bne     $v0, $t0, clear_loop
    addiu   $v1, $v1, 4

    or      $t1, $zero, $zero
    lui     $t2, 0x0007
    ori     $t2, $t2, 0xffff
loop:
    and     $t0, $a1, $t2
    sll     $t0, $t0, 2
    addu    $t0, $a0, $t0
    lw      $v0, 0($t0)
    srl     $v1, $a1, 1
    sll     $v0, $v0, 1
    xor     $v0, $v0, $v1
    and     $v1, $v0, $t2
    xor     $a2, $v0, $a2
    sll     $v1, $v1, 2
    sw      $a2, 0($t0)
    addu    $v1, $a0, $v1
    lw      $t0, 0($v1)
    or      $a2, $zero, $v0
    mul     $v0, $v0, $t0
    addiu   $t1, $t1, 1
    addu    $a1, $v0, $a1
    sw      $a1, 0($v1)
    bne     $a3, $t1, loop
    xor     $a1, $t0, $a1

    jr      $ra
    sll     $zero, $zero, 0
