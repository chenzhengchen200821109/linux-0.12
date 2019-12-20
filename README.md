# linux-0.12

## Build on Linux
    $ make help		// get help
    $ make  		// compile
    $ make boot-hd	// boot it on qemu with hard disk image

    $ make switch                // switch to another emulator, between qemu and bochs
    Switch to use emulator: bochs
    $ make boot VM=qemu|bochs    // specify the emulator, between qemu and bochs

    // edit .kernel_gdbinit(for kernel.sym) and .boot_gdbinit(for bootsect.sym and setup.sym) before debugging

    $ make debug-hd	// debug kernel.sym via qemu and start gdb automatically to connect it.
    $ make debug-hd DST=src/boot/bootsect.sym  // debug bootsect, can not debug code after ljmp
    $ make debug-hd DST=src/boot/setup.sym     // debug setup, can not debug after ljmp

## References
[tinyclub](https://github.com/tinyclub/linux-0.11-lab)
