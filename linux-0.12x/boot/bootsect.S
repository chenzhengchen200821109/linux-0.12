/*
 * SYS_SIZE is the number of clicks (16 bytes) to be loaded.
 * 0x3000 is 0x30000 bytes = 196kB, more than enough for current
 * versions of linux
 */
#include "linux/config.h"
SYSSIZE = DEF_SYSSIZE             

/*
 *	bootsect.s		(C) 1991 Linus Torvalds
 *	modified by Drew Eckhardt
 *
 * bootsect.s is loaded at 0x7c00 by the bios-startup routines, and moves
 * iself out of the way to address 0x90000, and jumps there.
 *
 * It then loads 'setup' directly after itself (0x90200), and the system
 * at 0x10000, using BIOS interrupts. 
 *
 * NOTE! currently system is at most 8*65536 bytes long. This should be no
 * problem, even in the future. I want to keep it simple. This 512 kB
 * kernel size should be enough, especially as this doesn't contain the
 * buffer cache as in minix
 *
 * The loader has been made as simple as possible, and continuos
 * read errors will result in a unbreakable loop. Reboot by hand. It
 * loads pretty fast by getting whole sectors at a time whenever possible.
 */

#.globl begtext, begdata, begbss, endtext, enddata, endbss
.section .text
.global begtext 
begtext:

.section .data
.global begdata 
begdata:

.section .bss 
.global .begbss 
begbss:

#.text

SETUPLEN = 4				    # nr of setup-sectors
BOOTSEG  = 0x07c0			    # original address of boot-sector
INITSEG  = DEF_INITSEG			# we move boot here(0x9000) - out of the way
SETUPSEG = DEF_SETUPSEG			# setup starts here(0x9020)
SYSSEG   = DEF_SYSSEG			# system loaded at 0x10000 (65536).
ENDSEG   = SYSSEG + SYSSIZE		# where to stop loading

# ROOT_DEV & SWAP_DEV are now written by "build".
ROOT_DEV = 0
SWAP_DEV = 0

.section .text
.global start
start:
.code16                     #Assemble for 16-bit mode
	movw $BOOTSEG, %ax 
	movw %ax, %ds 
	movw $INITSEG, %ax
	movw %ax, %es 
	movw $256, %cx          # 256*2=512Bytes
	subw %si, %si
	subw %di, %di
	rep movw
	ljmp $INITSEG, $go

go:	
    movw %cs, %ax 		
	movw $0xfef4, %dx	    # arbitrary value >>512 - disk parm size

	movw %ax, %ds 
	movw %ax, %es 
	pushw %ax

	movw %ax, %ss		    # put stack at 0x9ff00 - 12.
	movw %dx, %sp 

/*
 *	Many BIOS's default disk parameter tables will not 
 *	recognize multi-sector reads beyond the maximum sector number
 *	specified in the default diskette parameter tables - this may
 *	mean 7 sectors in some cases.
 *
 *	Since single sector reads are slow and out of the question,
 *	we must take care of this by creating new parameter tables
 *	(for the first disk) in RAM.  We will set the maximum sector
 *	count to 18 - the most we will encounter on an HD 1.44.  
 *
 *	High doesn't hurt.  Low does.
 *
 *	Segments are as follows: ds=es=ss=cs - INITSEG,
 *		fs = 0, gs = parameter table segment
 */
	pushw $0
	popw %fs 
	movw $0x78, %bx		# fs:bx is parameter table address(0x0000:0x0078)
	seg %fs
	lgs	(%bx), %si		# gs:si is source

	movw %dx, %di		# es:di is destination(0x9000:0xfef4)
	movw $6, %cx		# copy 12 bytes
	cld

	rep
	seg %gs
	movw

	movw %dx, %di 
	movb $18, 4(%di)	# patch sector count

	seg %fs
	movw %di, (%bx)	
	seg %fs
	movw %es, 2(%bx)

	popw %ax 
	movw %ax, %fs 
	movw %ax, %gs

/*
 * Reset(00h)
 * input parameters:
 *         ah - 00h, indicating the Reset Function.
 *         dl - Drive number.
 * output parameters:
 *         CY - Set if failure, else clear if success.
 *         ah - Status code if failure (00h if success).
 */
	
	xorb %ah, %ah		# reset FDC 
	xorb %dl, %dl       # drive number = 0
	int $0x13	

# load the setup-sectors(4 sectors) directly after the bootblock.
# Note that 'es' is already set up.

/*
 * Read Sectors(02h)
 * input parameters:
 *         ah - 02h, indicating the Read Sectors Function.
 *         al - Number of sectors.
 *         ch - Bottom 8 bits of track number
 *         cl - ttssssss, as follows:
 *                 tt = top two bits of 10-bit track number,
 *                 ssssss = 6-bit sector number.
 *         dh - Head number.
 *         dl - Drive number.
 *         ES:BX - Address of user buffer.
 * output parameters:
 *         CY - Set if failure, else clear if success.
 *         ah - Disk status code (00h if success).
 *         al - Number of sectors actually read.
 */

load_setup:
	xorw %dx, %dx			        # drive 0, head 0
	movw $0x0002, %cx	            # sector 2, track 0
	movw $0x0200, %bx 	            # address = 512, in INITSEG
	movw $0x0200+$SETUPLEN, %ax 	# service 2, nr of sectors
	int	$0x13			            # read it
	jnc	ok_load_setup		        # ok - continue

	pushw %ax			            # dump error code
	call print_nl
	movw %sp, %bp 
	call print_hex
	popw %ax	
	
	xorb %dl, %dl			        # reset FDC
	xorb %ah, %ah
	int	$0x13
	jmp	load_setup                  # re-read sectors

ok_load_setup:

# Get disk drive parameters, specifically nr of sectors/track

/*
 * Read Drive Parameters(08h)
 * The Read Drive Parameters disk BIOS function is called to return 
 * the geometry and disk type information for the specified drive. 
 * Additionally, the number of drives like the one specified is returned.
 * 
 * input parameters:
 *         ah - 08h, indicating the Read Drive Parameters Function.
 *         dl - Drive number.
 * output parameters:
 *         CY - Set if failure, else clear if success.
 *         ah - Disk status code (00h if success).
 *         bh - 00h (floppy drives only).
 *         bl - Drive type, as follows (floppy drives only).
 *                 01h - 5.25", 360KB, 40 tracks.
 *                 02h - 5.25", 1.2MB, 80 tracks.
 *                 03h - 3.5", 720KB, 80 tracks.
 *                 04h - 3.5", 1.44MB, 80 tracks.
 *         ch - Bottom 8 bits of maximum track number.
 *         cl - ttssssss, as follows:
 *                 tt = top two bits of 10-bit maximum track number,
 *                 ssssss = 6-bit maximum sector number.
 *         dh - Maximum head number.
 *         dl - Number of drives installed.
 *         ES:DI - Pointer to the diskette parameter table entry for a floppy dirve.
 */

	xorb %dl, %dl
	movb $0x08, %ah		                # AH=8 is get drive parameters
	int	$0x13
	xorb %ch, %ch 
	seg %cs
	movw %cx, $sectors
	movw $INITSEG, %ax 
	movw %ax, %es

# Print some inane message

/*
 * Read Cursor Position(03h)
 * input parameters:
 *         ah - 03h, indicating the Read Cursor Position Function.
 *         bh - Video page number (0 for first page).
 * output parameters:
 *         ax - 0000h.
 *         ch - Starting cursor scan line.
 *         cl - Ending cursor scan line.
 *         dh - Row number (0 = top-most row).
 *         dl - Column number (0 = left-most column).
 */
	movb $0x03, %ah             		# read cursor pos
	xorb %bh, %bh
	int	$0x10
	
/*
 * Write Char/Attr to Screen(09h)
 * input parameters:
 *         ah - 09h, indicating the Write Cha/Attr Pair Function.
 *         al - Character to store.
 *         bh - Video page number (0 for first page).
 *         bl - Attribute byte.
 *         cx - Repeat count.
 * output parameters:
 *         none.
 */
	movw $9, %cx 
	movw $0x0007, %bx	        		# page 0, attribute 7 (normal)
	mov	bp,#msg1
	movw $0x1301, %ax	        		# write string, move cursor
	int	$0x10

# ok, we've written the message, now
# we want to load the system (at 0x10000)

	movw $SYSSEG, %ax 
	movw %ax, %es               		# segment of 0x010000
	call read_it
	call kill_motor
	call print_nl

# After that we check which root-device to use. If the device is
# defined (!= 0), nothing is done and the given device is used.
# Otherwise, either /dev/PS0 (2,28) or /dev/at0 (2,8), depending
# on the number of sectors that the BIOS reports currently.

	seg %cs
	movw $root_dev, %ax 
	orw	%ax, %ax
	jne	root_defined
	seg %cs
	movw $sectors, %bx
	movw $0x0208, %ax	        		# /dev/ps0 - 1.2Mb
	cmpw $15, %bx 
	je	root_defined
	movw $0x021c, %ax	        		# /dev/PS0 - 1.44Mb
	cmpw $18, %bx 
	je	root_defined
undef_root:
	jmp undef_root
root_defined:
	seg %cs
	movw %ax, $root_dev

# after that (everyting loaded), we jump to the setup-routine 
# loaded directly after the bootblock:

	ljmp $SETUPSEG, $0

# This routine loads the system at address 0x10000, making sure
# no 64kB boundaries are crossed. We try to load it as fast as
# possible, loading whole tracks whenever we can.
#
# in:	es - starting address segment (normally 0x1000)
#
sread:	
    .word 1+SETUPLEN	                # sectors read of current track
head:	
    .word 0			                    # current head
track:	
    .word 0			                    # current track

read_it:
	movw %es, %ax
	test $0x0fff, %ax 
die:	
    jne die			                    # es must be at 64kB boundary
	xorw %bx, %bx		                # bx is starting address within segment
rp_read:
	movw %es, %ax
	cmpw $ENDSEG, %ax           		# have we loaded all yet?
	jb ok1_read                         # jmp if CF = 1 
	ret
ok1_read:
	seg %cs
	mov ax,sectors
	sub ax,sread
	mov cx,ax
	shl cx,#9
	add cx,bx
	jnc ok2_read
	je ok2_read
	xor ax,ax
	sub ax,bx
	shr $9, %ax
ok2_read:
	call read_track
	movw %ax, %cx
	addw $sread, %ax 
	seg %cs
	cmpw $sectors, %ax 
	jne ok3_read                        # jmp if ZF = 0
	movw $1, %ax 
	subw $head, %ax 
	jne ok4_read                        # jmp if ZF = 0
	inc $track
ok4_read:
	movw %ax, $head 
	xorw %ax, %ax
ok3_read:
	movw %ax, $sread
	shl $9, %cx 
	addw %cx, %bx
	jnc rp_read                         # jmp if CF = 0
	movw %es, %ax
	addb $0x10, %ah 
	movw %ax, %es 
	xorw %bx, %bx
	jmp rp_read

/*
 *
 */ 


/*
 * Write Teletype Mode(0eh)
 * The Write Teletype video BIOS function is called to write a character 
 * to the display at the current cursor location, advancing the cursor to 
 * the next column. If the column would extend off the right edge of the 
 * screen, the column is reset to 0, and the row is incremented. If the row 
 * would move off the end of the screen, then the entire screen is scrolled.
 * 
 * input parameters:
 *         ah - 0eh, indicating the Write Teletype Mode Function.
 *         al - Character to write.
 *         bh - Video page number (0 for first page).
 *         bl - Foreground color, but only for graphics modes.
 * output parameters:
 *         none.
 */
read_track:
	pusha
	pusha	
	movw $0x0e2e, %ax                 	# loading... message 2e = .
	movw $7, %bx
 	int	$0x10
	popa		

/*
 * Read Sectors(02h)
 * The Read Sectors disk BIOS function is called to read a sector 
 * run from the specified drive into a user-defined buffer. The read 
 * must not span a track or head boundary, and the buffer must not
 * cross a 64KB DMA boundary in the physical address space.
 * 
 * input parameters:
 *         ah - 02h, indicating the Read Sectors Function.
 *         al - Number of sectors.
 *         ch - Bottom 8 bits of track number (0-based).
 *         cl - ttssssss, as follows:
 *                 tt = top two bits of 10-bit track number,
 *                 ssssss = 6-bit sector number (1-based).
 *         dh - Head number (0-based). 
 *         dl - Drive number.
 *         ES:BX - Address of user buffer.
 * output parameters:
 *         CY - Set if failure, else clear if success.
 *         ah - Disk status code (00h if success).
 *         al - Number of sectors actually read.
 */
	movw $track, %dx 
	movw $sread, %cx
	inc %cx
	movb %dl, %ch 
	mov dx,head
	mov dh,dl
	and dx,#0x0100
	movb $2, %ah
	
	pushw %dx				    # save for error dump
	pushw %cx
	pushw %bx
	pushw %ax

	int $0x13
	jc bad_rt                   # if failure, go to bad_tr.
	addw $8, %sp   	
	popa
	ret

bad_rt:	
    pushw %ax				    # save error code
	call print_all			    # ah = error, al = read
	
/*
 * Reset - The Reset disk BIOS function is called to reset the disk 
 *         subsystem (ROM, RAM, RFD, floppy, and IDE). This function 
 *         is used during POST and also whenever an error occurs as 
 *         a result of a disk operation.
 */
	xorb %ah, %ah               # reset
	xorb %dl, %dl
	int $0x13
	

	addw $10, %sp
	popa	
	jmp read_track              # RETRY!!!

/*
 *	print_all is for debugging purposes.  
 *	It will print out all of the registers.  The assumption is that this is
 *	called from a routine, with a stack frame like
 *	dx 
 *	cx
 *	bx
 *	ax
 *	error
 *	ret <- sp
 *
*/
print_all:
	movw $5, %cx        		# error code + 4 registers
	movw %sp, %bp	

print_loop:
	pushw %cx		            # save count left
	call print_nl	            # nl for readability
	jae	no_reg		            # see if register name is needed (jmp if CF = 0)
	
 
/*
 * Write Teletype Mode(0eh)
 * The Write Teletype video BIOS function is called to write a character 
 * to the display at the current cursor location, advancing the cursor to 
 * the next column. If the column would extend off the right edge of the 
 * screen, the column is reset to 0, and the row is incremented. If the row 
 * would move off the end of the screen, then the entire screen is scrolled.
 * 
 * input parameters:
 *         ah - 0eh, indicating the Write Teletype Mode Function.
 *         al - Character to write.
 *         bh - Video page number (0 for first page).
 *         bl - Foreground color, but only for graphics modes.
 * output parameters:
 *         none.
 */
	mov	$0x0e05 + $0x41 - $1, %ax 
	subb %cl, %al 
	int	$0x10

	movb $0x58, %al             # character 'X'
	int	$0x10

	movb $0x3a,	%al             # character ':'
	int	$0x10

no_reg:
	addw $2, %bp                # next register
	call print_hex	            # print it
	popw %cx
	loop print_loop
	ret

/*
 * Write Teletype Mode(0eh)
 * The Write Teletype video BIOS function is called to write a character 
 * to the display at the current cursor location, advancing the cursor to 
 * the next column. If the column would extend off the right edge of the 
 * screen, the column is reset to 0, and the row is incremented. If the row 
 * would move off the end of the screen, then the entire screen is scrolled.
 * 
 * input parameters:
 *         ah - 0eh, indicating the Write Teletype Mode Function.
 *         al - Character to write.
 *         bh - Video page number (0 for first page).
 *         bl - Foreground color, but only for graphics modes.
 * output parameters:
 *         none.
 */
print_nl:
	movw $0x0e0d, %ax                   # CR
	int	$0x10
	movb $0xa, %al	                    # LF
	int $0x10
	ret

/*
 *	print_hex is for debugging purposes, and prints the word
 *	pointed to by ss:bp in hexadecmial.
 */

print_hex:
	movw $4, %cx                		# 4 hex digits
	movw (%bp),	%dx                 	# load word into %dx
print_digit:
	rol	dx, #4		                    # rotate so that lowest 4 bits are used
	mov	ah, #0xe	
	mov	al, dl		                    # mask off so we have only next nibble
	and	al, #0xf
	add	al, #0x30	                    # convert to 0 based digit, '0'
	cmp	al, #0x39	                    # check for overflow
	jbe	good_digit
	add	al, #0x41 - 0x30 - 0xa 	! 'A' - '0' - 0xa

good_digit:
	int	$0x10
	loop print_digit
	ret


/*
 * This procedure turns off the floppy drive motor, so
 * that we enter the kernel in a known state, and
 * don't have to worry about it later.
 */
kill_motor:
	pushw %dx
	movw $0x3f2, %dx 
	xorb %al, %al
	outb
	popw %dx
	ret

sectors:
	.word 0

msg1:
	.byte 13, 10
	.ascii "Loading"

.org 506
swap_dev:
	.word SWAP_DEV
root_dev:
	.word ROOT_DEV
boot_flag:
	.word 0xAA55

.section .text
endtext:
.section .data
enddata:
.section .bss
endbss:

