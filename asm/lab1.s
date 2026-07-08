.org 0x0
.set noreorder
.set noat
.text
.global __start
.global _start

__start:
_start:
    ori   $t0, $zero, 0x1
    ori   $t1, $zero, 0x1
    ori   $s1, $zero, 0x4
    ori   $t4, $zero, 0x100
    lui   $a0, 0x8040
    addu  $t5, $a0, $t4

loop:
    addu  $t2, $t0, $t1
    ori   $t0, $t1, 0x0
    ori   $t1, $t2, 0x0
    sw    $t1, 0($a0)
    lw    $t3, 0($a0)
    bne   $t1, $t3, end
    ori   $zero, $zero, 0
    addu  $a0, $a0, $s1
    bne   $a0, $t5, loop
    ori   $zero, $zero, 0

end:
    bne   $s1, $zero, end
    ori   $zero, $zero, 0
