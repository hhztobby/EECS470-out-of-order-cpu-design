    li 	x2,0
	li 	x3,0
	li  x5,0
	li  x6,0
	li  x7,0
	li  x8,0
	li    x4, 0x1000
    li    x1, 0
    nop
    nop
loop:	addi x1, x1, 0x1
    addi	x2,	x2,	0x8 #
    addi	x3, x3, 0x8 #
	addi 	x5, x5, 0x8
	addi 	x6, x6, 0x8
	addi 	x7, x7, 0x8
	addi 	x8, x8, 0x8
	addi 	x9, x9, 0x8
	addi 	x10, x10, 0x8
    bne	x1,	x4,	loop #
    wfi
