	.code16
# rewrite with AT&T syntax by falcon <wuzhangjin@gmail.com> at 081012
#
# SYS_SIZE is the number of clicks (16 bytes) to be loaded.
# 0x3000 is 0x30000 bytes = 196kB, more than enough for current
# versions of linux
#
	.equ SYSSIZE, SYS_SIZE
#
#	bootsect.s		(C) 1991 Linus Torvalds
#
# bootsect.s is loaded at 0x7c00 by the bios-startup routines, and moves
# iself out of the way to address 0x90000, and jumps there.
#
# It then loads 'setup' directly after itself (0x90200), and the system
# at 0x10000, using BIOS interrupts. 
#
# NOTE! currently system is at most 8*65536 bytes (512KB) long. This should 
# be no problem, even in the future. I want to keep it simple. This 512 kB
# kernel size should be enough, especially as this doesn't contain the
# buffer cache as in minix
#
# The loader has been made as simple as possible, and continuos
# read errors will result in a unbreakable loop. Reboot by hand. It
# loads pretty fast by getting whole sectors at a time whenever possible.
# *********************************************************************************************
# boot被bios－启动子程序加载至7c00h（31k）处，并将自己移动到了地址90000h（576k）处，并跳转至那里。
# 它然后使用BIOS中断将'setup'直接加载到自己的后面（90200h）（576.5k），并将system加载到地址10000h处。
# 注意：目前的内核系统最大长度限制为（8*65536）（512kB）字节，即使是在将来这也应该没有问题的。
# 我想让它保持简单明了。这样512k的最大内核长度应该足够了，尤其是这里没有象minix中一样包含缓冲区
# 高速缓冲。
# 加载程序已经做的够简单了，所以持续的读出错将导致死循环。只能手工重启。只要可能，通过一次取
# 所有的扇区，加载过程可以做的很快的。
# *********************************************************************************************

	.global _start, begtext, begdata, begbss, endtext, enddata, endbss
	.text
	begtext:
	.data
	begdata:
	.bss
	begbss:
	.text

	.equ SETUPLEN, 4		# nr of setup-sectors(setup程序的扇区数)
	.equ BOOTSEG, 0x07c0	# original address of boot-sector(bootsect的原始地址)
	.equ INITSEG, 0x9000	# we move boot here(将bootsect移到这里)
	.equ SETUPSEG, 0x9020	# setup starts here(setup程序从这里开始)
	.equ SYSSEG, 0x1000		# system loaded at 0x10000 (65536).(system模块加载到10000(64kB)处)
	.equ ENDSEG, SYSSEG + SYSSIZE	# where to stop loading(停止加载的段地址)

    # ROOT_DEV:	0x000 - same type of floppy as boot.
    # 0x301 - first partition on first drive etc(根文件系统设备在第一个硬盘的第一个分区上)
    # 这是Linux老式的硬盘命名方式，具体值的含义如下：
	# 设备号 ＝ 主设备号*256 ＋ 次设备号(也即 dev_no = (major<<8 + minor)
	# (主设备号：1－内存，2－磁盘，3－硬盘，4－ttyx，5－tty，6－并行口，7－非命名管道)
	# 300 - /dev/hd0 － 代表整个第1个硬盘
	# 301 - /dev/hd1 － 第1个盘的第1个分区
	# ... ...
	# 304 - /dev/hd4 － 第1个盘的第4个分区
	# 305 - /dev/hd5 － 代表整个第2个硬盘
	# 306 - /dev/hd6 － 第2个盘的第1个分区
	# ... ...
	# 309 - /dev/hd9 － 第1个盘的第4个分区 
	.equ ROOT_DEV, 0x301
	ljmp $BOOTSEG, $_start
_start:
    # 以下10行作用是将自身(bootsect)从目前段位置07c0h(31k)
	# 移动到9000h(576k)处，共256字(512字节)，然后跳转到
	# 移动后代码的 go 标号处，也即本程序的下一语句处。
	mov	$BOOTSEG, %ax
	mov	%ax, %ds            # 将ds段寄存器置为7C0h
	mov	$INITSEG, %ax
	mov	%ax, %es            # 将es段寄存器置为9000h
	mov	$256, %cx           # 移动计数值 ＝ 256字 = 512 字节(见指令movsw)
	sub	%si, %si            # 源地址ds:si = 07C0h:0000h
	sub	%di, %di            # 目的地址 es:di = 9000h:0000h 
	rep	
	movsw
	ljmp $INITSEG, $go
go:	mov	%cs, %ax
	mov	%ax, %ds
	mov	%ax, %es            # 将ds、es和ss都置成移动后代码所在的段处（9000h）。
    # 由于程序中有堆栈操作（push，pop，call），因此必须设置堆栈
    # put stack at 0x9ff00(将堆栈指针sp指向9ff00h（即9000h:0ff00h）处)
    # 由于代码段移动过了，所以要重新设置堆栈段的位置。
	# sp只要指向远大于512偏移（即地址90200h）处都可以。
    # 因为从90200h地址开始处还要放置setup程序，而此时setup程序大约为4个扇区，
    # 因此sp要指向大于（200h + 200h*4 + 堆栈大小）处。
	mov	%ax, %ss
	mov	$0xFF00, %sp		# arbitrary value >> 512

    # load the setup-sectors directly after the bootblock.
    # Note that 'es' is already set up.
    # 在bootsect程序块后紧跟着加载setup模块的代码数据。
    # 注意es已经设置好了。（在移动代码时es已经指向目的段地址处9000h）。
load_setup:
    # 以下10行的用途是利用BIOS中断INT 13h将setup模块从磁盘第2个扇区
	# 开始读到90200h开始处，共读4个扇区。如果读出错，则复位驱动器，并
	# 重试，没有退路。
	# INT 13h 的使用方法如下：
	# ah = 02h - 读磁盘扇区到内存；al = 需要读出的扇区数量；
	# ch = 磁道（柱面）号的低8位；cl = 开始扇区（0－5位），磁道号高2位（6－7）；
	# dh = 磁头号；dl = 驱动器号（如果是硬盘则要置为7）；
	# es:bx ->指向数据缓冲区；如果出错则CF标志置位。
	mov	$0x0000, %dx		# drive 0, head 0
	mov	$0x0002, %cx		# sector 2, track 0
	mov	$0x0200, %bx		# address = 512, in INITSEG
	.equ AX, 0x0200+SETUPLEN
	mov $AX, %ax		    # service 2, nr of sectors
	int	$0x13			    # read it
	jnc	ok_load_setup		# ok - continue
	mov	$0x0000, %dx
	mov	$0x0000, %ax		# reset the diskette
	int	$0x13
	jmp	load_setup

ok_load_setup:

    # Get disk drive parameters, specifically nr of sectors/track
    # 取磁盘驱动器的参数，特别是每道的扇区数量。
    # 取磁盘驱动器参数INT 13h调用格式和返回信息如下：
    # ah = 08h, dl = 驱动器号（如果是硬盘则要置位7为1）。
    # 返回信息：
    # 如果出错则CF置位，并且ah = 状态码。
    # ah = 0, al = 0, bl = 驱动器类型（AT/PS2）
    # ch = 最大磁道号的低8位，cl = 每磁道最大扇区数（位0-5），最大磁道号高2位（位6-7）
    # dh = 最大磁头数，       电力＝ 驱动器数量，
    # es:di -> 软驱磁盘参数表。
	mov	$0x00, %dl
	mov	$0x0800, %ax		# AH=8 is get drive parameters
	int	$0x13
	mov	$0x00, %ch
	#seg cs
	mov	%cx, %cs:sectors+0	# %cs means sectors is in %cs
    # 因为上面取磁盘参数中断改掉了es的值，这里重新改回
	mov	$INITSEG, %ax
	mov	%ax, %es

    # Print some inane message
    # 显示一些信息（'Loading system ... '回车换行，共24个字符）
	mov	$0x03, %ah		    # read cursor pos
	xor	%bh, %bh
	int	$0x10
	
	mov	$24, %cx            # 共24个字符
	mov	$0x0007, %bx		# page 0, attribute 7 (normal)
	#lea	msg1, %bp
	mov $msg1, %bp          # 指向要显示的字符串
	mov	$0x1301, %ax		# write string, move cursor
	int	$0x10

    # ok, we've written the message, now
    # we want to load the system (at 0x10000)

	mov	$SYSSEG, %ax    # segment of 0x10000(64KB)
	mov	%ax, %es		# 读磁盘上system模块，es为输入参数
	call read_it
	call kill_motor

# After that we check which root-device to use. If the device is
# defined (#= 0), nothing is done and the given device is used.
# Otherwise, either /dev/PS0 (2,28) or /dev/at0 (2,8), depending
# on the number of sectors that the BIOS reports currently.
# 此后，我们检查要使用哪个根文件系统设备（简称根设备）。如果已经指定了设备（!=0）
# 就直接使用给定的设备。否则就需要根据BIOS报告的每磁道扇区数来
# 确定到底使用/dev/PS0(2,28)还是/dev/at0(2,8)。
# 上面一行中两个设备文件的含义：
# 在Linux中软驱的主设备号是2（参加第43行注释），次设备号 = type*4 + nr, 其中
# nr为0－3分别对应软驱A、B、C或D；type是软驱的类型（2->1.2M或7->1.44M等）。
# 因为7*4 + 0 = 28，所以/dev/PS0(2,28)指的是1.44M A驱动器，其设备号是021c
# 同理 /dev/at0(2,8)指的是1.2M A驱动器，其设备号是0208。

	#seg cs
	mov	%cs:root_dev+0, %ax
	cmp	$0, %ax             # 如果 ax != 0, 转到root_defined
	jne	root_defined
	#seg cs
	mov	%cs:sectors+0, %bx  # 取上面保存的每磁道扇区数。如果sectors=15
                            # 则说明是1.2Mb的驱动器；如果sectors=18，则说明是
						    # 1.44Mb软驱。因为是可引导的驱动器，所以肯定是A驱。
	mov	$0x0208, %ax		# /dev/ps0 - 1.2Mb
	cmp	$15, %bx
	je	root_defined
	mov	$0x021c, %ax		# /dev/PS0 - 1.44Mb
	cmp	$18, %bx
	je	root_defined
undef_root:
	jmp undef_root          # 如果都不一样，则死循环（死机）
root_defined:
	#seg cs
	mov	%ax, %cs:root_dev+0 # 将检查过的设备号保存起来

# after that (everyting loaded), we jump to
# the setup-routine loaded directly after
# the bootblock:
# 到此，所有程序都加载完毕，我们就跳转到被
# 加载在bootsect后面的setup程序去。

	ljmp	$SETUPSEG, $0   # 跳转到9020:0000（setup程序的开始处）

# This routine loads the system at address 0x10000, making sure
# no 64kB boundaries are crossed. We try to load it as fast as
# possible, loading whole tracks whenever we can.
#
# in:	es - starting address segment (normally 0x1000)
#
# 该子程序将系统模块加载到内存地址10000h处，并确定没有跨越64kB的内存边界。
# 我们试图尽快地进行加载，只要可能，就每次加载整条磁道的数据
sread:	.word 1+ SETUPLEN	# sectors read of current track(当前磁道中已读的扇区数。开始时已经读进1扇区的引导扇区)
head:	.word 0			    # current head(当前磁头号)
track:	.word 0			    # current track(当前磁道号)

read_it:
	mov	%es, %ax
	test $0x0fff, %ax       # 测试输入的段值。必须位于内存地址64KB边界处，否则进入死循环
die:
    jne die		        	# es must be at 64kB boundary
	xor %bx, %bx		    # bx is starting address within segment
rp_read:
	mov %es, %ax
    # 判断是否已经读入全部数据。比较当前所读段是否就是系统数据末端所处的段（#ENDSEG），如果
    # 不是就跳转至下面ok1_read标号处继续读数据。否则退出子程序返回。
 	cmp $ENDSEG, %ax	    # have we loaded all yet?
	jb	ok1_read
	ret
ok1_read:
    # 计算和验证当前磁道需要读取的扇区数，放在ax寄存器中。
    # 根据当前磁道还未读取的扇区数以及段内数据字节开始偏移位置，计算如果全部读取这些
    # 未读扇区，所读总字节数是否会超过64KB段长度的限制。若会超过，则根据此次最多能读
    # 入的字节数（64KB - 段内偏移位置），反算出此次需要读取的扇区数。
	#seg cs
	mov	%cs:sectors+0, %ax
	sub	sread, %ax
	mov	%ax, %cx
	shl	$9, %cx
	add	%bx, %cx
	jnc ok2_read
	je ok2_read
	xor %ax, %ax
	sub %bx, %ax
	shr $9, %ax
ok2_read:
	call read_track
	mov %ax, %cx
	add sread, %ax
	#seg cs
	cmp %cs:sectors+0, %ax
	jne ok3_read
	mov $1, %ax
	sub head, %ax
	jne ok4_read
	incw track 
ok4_read:
	mov	%ax, head
	xor	%ax, %ax
ok3_read:
	mov	%ax, sread
	shl	$9, %cx
	add	%cx, %bx
	jnc	rp_read
	mov	%es, %ax
	add	$0x1000, %ax
	mov	%ax, %es
	xor	%bx, %bx
	jmp	rp_read

read_track:
	push %ax
	push %bx
	push %cx
	push %dx
	mov	track, %dx
	mov	sread, %cx
	inc	%cx
	mov	%dl, %ch
	mov	head, %dx
	mov	%dl, %dh
	mov	$0, %dl
	and	$0x0100, %dx
	mov	$2, %ah
	int	$0x13
	jc	bad_rt
	pop	%dx
	pop	%cx
	pop	%bx
	pop	%ax
	ret
bad_rt:	mov	$0, %ax
	mov	$0, %dx
	int	$0x13
	pop	%dx
	pop	%cx
	pop	%bx
	pop	%ax
	jmp	read_track

#
# This procedure turns off the floppy drive motor, so
# that we enter the kernel in a known state, and
# don't have to worry about it later.
# 这个子程序用于关闭软驱的马达，这样我们进入内核
# 后它处于已知状态，以后也就无须担心它了。 
kill_motor:
	push %dx
	mov	$0x3f2, %dx                 # 软驱控制卡的驱动端口，只写
	mov	$0, %al                     # A驱动器，关闭FDC，禁止DMA和中断请求，关闭马达
	outsb                           # 将al中的内容输出到dx指定的端口去
	pop	%dx
	ret

sectors:
	.word 0                         # 存放当前启动软盘每磁道的扇区数

msg1:
	.byte 13,10                     # 回车、换行的ASCII码
	.ascii "Loading system ..."
	.byte 13,10,13,10
    # 表示下面语句从地址508(1FC)开始，所以root_dev
    # 在启动扇区的第508开始的2个字节中。
	.org 508
root_dev:
	.word ROOT_DEV                  # 这里存放根文件系统所在的设备号（init/main.c中会用）
boot_flag:
	.word 0xAA55                    # 启动扇区标识
	
	.text
	endtext:
	.data
	enddata:
	.bss
	endbss:
