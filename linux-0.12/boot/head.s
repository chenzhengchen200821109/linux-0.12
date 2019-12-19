/*
 *  linux/boot/head.s
 *
 *  (C) 1991  Linus Torvalds
 */

/*
 *  head.s contains the 32-bit startup code.(head.s 含有32 位启动代码。)
 *
 * NOTE!!! Startup happens at absolute address 0x00000000, which is also where
 * the page directory will exist. The startup code will be overwritten by
 * the page directory.
 * 注意!!! 32 位启动代码是从绝对地址0x00000000 开始的，这里也同样
 * 是页目录将存在的地方，因此这里的启动代码将被页目录覆盖掉。
 */
.text
.globl idt,gdt,pg_dir,tmp_floppy_area
pg_dir:                             # 页目录将会存放在这里
startup_32:
    # 再次注意!!! 这里已经处于32 位运行模式，因此这里的$0x10 并不是把地址0x10 装入各
    # 个段寄存器，它现在其实是全局段描述符表中的偏移值，或者更正确地说是一个描述符表
    # 项的选择符。有关选择符的说明请参见setup.s 中的说明。这里$0x10 的含义是请求特权
    # 级0(位0-1=0)、选择全局描述符表(位2=0)、选择表中第2 项(位3-15=2)。它正好指向表中
    # 的数据段描述符项。（描述符的具体数值参见前面setup.s ）。下面代码的含义是：
    # 置ds,es,fs,gs 中的选择符为setup.s 中构造的数据段（全局段描述符表的第2 项）=0x10，
    # 并将堆栈放置在数据段中的_stack_start 数组内，然后使用新的中断描述符表和全局段
    # 描述表.新的全局段描述表中初始内容与setup.s 中的完全一样。
	movl $0x10, %eax
	mov %ax, %ds
	mov %ax, %es
	mov %ax, %fs
	mov %ax, %gs
	#lss _stack_start, %esp           # 表示_stack_start -> ss:esp，设置系统堆栈。
	lss stack_start, %esp 						         # stack_start 定义在kernel/sched.c，69 行。
	call setup_idt                   # 调用设置中断描述符表子程序
	call setup_gdt                   # 调用设置全局描述符表子程序
	movl $0x10,%eax		             # reload all the segment registers
	mov %ax,%ds		                 # after changing gdt. CS was already
	mov %ax,%es		                 # reloaded in 'setup_gdt'
	mov %ax,%fs
	mov %ax,%gs
	#lss _stack_start, %esp
    lss stack_start, %esp
    # 以下5行用于测试A20 地址线是否已经开启。采用的方法是向内存地址0x000000 处写入任意
    # 一个数值，然后看内存地址0x100000(1M)处是否也是这个数值。如果一直相同的话，就一直
    # 比较下去，也即死循环、死机。表示地址A20 线没有选通，结果内核就不能使用1M 以上内存。 
	xorl %eax, %eax
1:	incl %eax		                 # check that A20 really IS enabled
	movl %eax,0x000000	             # loop forever if it isn't
	cmpl %eax,0x100000
	je 1b
/*
 * NOTE! 486 should set bit 16, to check for write-protect in supervisor
 * mode. Then it would be unnecessary with the "verify_area()"-calls.
 * 486 users probably want to set the NE (#5) bit also, so as to use
 * int 16 for math errors.
 */
# 注意! 在下面这段程序中，486 应该将位16 置位，以检查在超级用户模式下的写保护,
# 此后"verify_area()"调用中就不需要了。486 的用户通常也会想将NE(;//5)置位，以便
# 对数学协处理器的出错使用int 16。
# 下面这段程序用于检查数学协处理器芯片是否存在。方法是修改控制寄存器CR0，在假设
# 存在协处理器的情况下执行一个协处理器指令，如果出错的话则说明协处理器芯片不存
# 在，需要设置CR0 中的协处理器仿真位EM（位2），并复位协处理器存在标志MP（位1）。
	movl %cr0, %eax		             # check math chip
	andl $0x80000011, %eax	         # Save PG,PE,ET
    /* "orl $0x10020,%eax" here for 486 might be good */
	orl $2, %eax		             # set MP
	movl %eax, %cr0
	call check_x87
	jmp after_page_tables

/*
 * We depend on ET to be correct. This checks for 287/387.
 */
check_x87:
	fninit
	fstsw %ax
	cmpb $0,%al
	je 1f			                 /* no coprocessor: have to set bits */
	movl %cr0,%eax
	xorl $6,%eax		             /* reset MP, set EM */
	movl %eax,%cr0
	ret
.align 2                             # 这里".align 2"的含义是指存储边界对齐调整
1:	.byte 0xDB,0xE4		             /* fsetpm for 287, ignored by 387 */
	ret

/*
 *  setup_idt
 *
 *  sets up a idt with 256 entries pointing to
 *  ignore_int, interrupt gates. It then loads
 *  idt. Everything that wants to install itself
 *  in the idt-table may do so themselves. Interrupts
 *  are enabled elsewhere, when we can be relatively
 *  sure everything is ok. This routine will be over-
 *  written by the page tables.
 */
# 下面这段是设置中断描述符表子程序setup_idt
# 将中断描述符表idt 设置成具有256 个项，并都指向ignore_int 中断门。然后加载
# 中断描述符表寄存器(用lidt 指令)。真正实用的中断门以后再安装。当我们在其它
# 地方认为一切都正常时再开启中断。该子程序将会被页表覆盖掉。
setup_idt:
	lea ignore_int, %edx
	movl $0x00080000, %eax
	movw %dx, %ax		/* selector = 0x0008 = cs */
	movw $0x8E00, %dx	/* interrupt gate - dpl=0, present */

	lea idt, %edi
	mov $256, %ecx
rp_sidt:
	movl %eax, (%edi)
	movl %edx, 4(%edi)
	addl $8, %edi
	dec %ecx
	jne rp_sidt
	lidt idt_descr
	ret

/*
 *  setup_gdt
 *
 *  This routines sets up a new gdt and loads it.
 *  Only two entries are currently built, the same
 *  ones that were built in init.s. The routine
 *  is VERY complicated at two whole lines, so this
 *  rather long comment is certainly needed :-).
 *  This routine will beoverwritten by the page tables.
 */
# 这个子程序设置一个新的全局描述符表gdt，并加载。此时仅创建了两个表项，与前
# 面的一样。该子程序只有两行，“非常的”复杂，所以当然需要这么长的注释了:)。
setup_gdt:
	lgdt gdt_descr
	ret

/*
 * I put the kernel page tables right after the page directory,
 * using 4 of them to span 16 Mb of physical memory. People with
 * more than 16MB will have to expand this.
 */
# Linus 将内核的内存页表直接放在页目录之后，使用了4 个表来寻址16 Mb 的物理内存。
# 如果你有多于16 Mb 的内存，就需要在这里进行扩充修改。
# 每个页表长为4 Kb 字节，而每个页表项需要4 个字节，因此一个页表共可以存放1000 个，
# 表项如果一个表项寻址4 Kb 的地址空间，则一个页表就可以寻址4 Mb 的物理内存。页表项
# 的格式为：项的前0-11 位存放一些标志，如是否在内存中(P 位0)、读写许可(R/W 位1)、
# 普通用户还是超级用户使用(U/S 位2)、是否修改过(是否脏了)(D 位6)等；表项的位12-31 
# 是页框地址，用于指出一页内存的物理起始地址。
.org 0x1000                     # 从偏移0x1000 处开始是第1 个页表（偏移0 开始处将存放页表目录）。
pg0:

.org 0x2000
pg1:

.org 0x3000
pg2:

.org 0x4000
pg3:

.org 0x5000                     # 定义下面的内存数据块从偏移0x5000 处开始
/*
 * tmp_floppy_area is used by the floppy-driver when DMA cannot
 * reach to a buffer-block. It needs to be aligned, so that it isn't
 * on a 64kB border.
 */
# 当DMA（直接存储器访问）不能访问缓冲块时，下面的tmp_floppy_area 内存块
# 就可供软盘驱动程序使用。其地址需要对齐调整，这样就不会跨越64kB 边界。

tmp_floppy_area:
	.fill 1024,1,0
# 下面这几个入栈操作(pushl)用于为调用/init/main.c 程序和返回作准备。
# 前面3 个入栈指令不知道作什么用的，也许是Linus 用于在调试时能看清机器码用的.。
# 139 行的入栈操作是模拟调用main.c 程序时首先将返回地址入栈的操作，所以如果
# main.c 程序真的退出时，就会返回到这里的标号L6 处继续执行下去，也即死循环。
# 140 行将main.c 的地址压入堆栈，这样，在设置分页处理（setup_paging）结束后
# 执行'ret'返回指令时就会将main.c 程序的地址弹出堆栈，并去执行main.c 程序去了。
after_page_tables:
	pushl $0		# These are the parameters to main :-)
	pushl $0
	pushl $0
	pushl $L6		# return address for main, if it decides to.
	#pushl $_main
    pushl $main
	jmp setup_paging
L6:
	jmp L6			# main should never return here, but
				    # just in case, we know what happens.

/* This is the default interrupt "handler" :-) */
int_msg:
	.asciz "Unknown interrupt\n\r"
.align 2
ignore_int:
	pushl %eax
	pushl %ecx
	pushl %edx
	push %ds
	push %es
	push %fs
	movl $0x10, %eax
	mov %ax, %ds
	mov %ax, %es
	mov %ax, %fs
	pushl $int_msg          # 把调用printk 函数的参数指针（地址）入栈
	call printk            # 该函数在/kernel/printk.c 中
                            # '_printk'是printk 编译后模块中的内部表示法
	popl %eax
	pop %fs
	pop %es
	pop %ds
	popl %edx
	popl %ecx
	popl %eax
	iret


/*
 * Setup_paging
 *
 * This routine sets up paging by setting the page bit
 * in cr0. The page tables are set up, identity-mapping
 * the first 16MB. The pager assumes that no illegal
 * addresses are produced (ie >4Mb on a 4Mb machine).
 *
 * NOTE! Although all physical memory should be identity
 * mapped by this routine, only the kernel page functions
 * use the >1Mb addresses directly. All "normal" functions
 * use just the lower 1Mb, or the local data space, which
 * will be mapped to some other place - mm keeps track of
 * that.
 *
 * For those with more memory than 16 Mb - tough luck. I've
 * not got it, why should you :-) The source is here. Change
 * it. (Seriously - it shouldn't be too difficult. Mostly
 * change some constants etc. I left it at 16Mb, as my machine
 * even cannot be extended past that (ok, but it was cheap :-)
 * I've tried to show which constants to change by having
 * some kind of marker at them (search for "16Mb"), but I
 * won't guarantee that's all :-( )
 */
# 这个子程序通过设置控制寄存器cr0 的标志（PG 位31）来启动对内存的分页处理
# 功能，并设置各个页表项的内容，以恒等映射前16 MB 的物理内存。分页器假定
# 不会产生非法的地址映射（也即在只有4Mb 的机器上设置出大于4Mb 的内存地址）。
# 注意！尽管所有的物理地址都应该由这个子程序进行恒等映射，但只有内核页面管
# 理函数能直接使用>1Mb 的地址。所有“一般”函数仅使用低于1Mb 的地址空间，或
# 者是使用局部数据空间，地址空间将被映射到其它一些地方去-- mm(内存管理程序)
# 会管理这些事的。
# 对于那些有多于16Mb 内存的家伙- 太幸运了，我还没有，为什么你会有:-)。代码就
# 在这里，对它进行修改吧。（实际上，这并不太困难的。通常只需修改一些常数等。
# 我把它设置为16Mb，因为我的机器再怎么扩充甚至不能超过这个界限（当然，我的机 
# 器很便宜的:-)）。我已经通过设置某类标志来给出需要改动的地方（搜索“16Mb”），
# 但我不能保证作这些改动就行了 :-( )
.align 2
setup_paging:
	movl $1024*5, %ecx		/* 5 pages - pg_dir+4 page tables */
	xorl %eax, %eax
	xorl %edi, %edi			/* pg_dir is at 0x000 */
	cld;rep;stosl
	movl $pg0+7, pg_dir		/* set present bit/user r/w */
	movl $pg1+7, pg_dir+4		/*  --------- " " --------- */
	movl $pg2+7, pg_dir+8		/*  --------- " " --------- */
	movl $pg3+7, pg_dir+12		/*  --------- " " --------- */
	movl $pg3+4092, %edi
	movl $0xfff007, %eax		/*  16Mb - 4096 + 7 (r/w user,p) */
	std
1:	stosl			    /* fill pages backwards - more efficient :-) */
	subl $0x1000, %eax
	jge 1b
	xorl %eax, %eax		/* pg_dir is at 0x0000 */
	movl %eax, %cr3		/* cr3 - page directory start */
	movl %cr0, %eax
	orl $0x80000000, %eax
	movl %eax, %cr0		/* set paging (PG) bit */
	ret			        /* this also flushes prefetch-queue */

.align 2
.word 0
idt_descr:
	.word 256*8-1		# idt contains 256 entries
	.long idt
.align 2
.word 0
gdt_descr:
	.word 256*8-1		# so does gdt (not that that's any
	.long gdt		    # magic number, but it works for me :^)

	.align 8
idt:	
    .fill 256,8,0		# idt is uninitialized

gdt: 
    .quad 0x0000000000000000	/* NULL descriptor */
	.quad 0x00c09a0000000fff	    /* 16Mb */
	.quad 0x00c0920000000fff	    /* 16Mb */
	.quad 0x0000000000000000	    /* TEMPORARY - don't use */
	.fill 252,8,0			        /* space for LDT's and TSS's etc */
