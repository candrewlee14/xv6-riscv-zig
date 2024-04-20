# xv6-riscv-zig

This compiles the xv6-riscv project with the Zig build system, and supports incrementally swapping out C code for Zig code.
There are examples of kernel code and user programs using both C and Zig.

Can build on Linux, OSX, and even Windows with only these system dependencies:
- Zig 0.12 ([download here](https://ziglang.org/download))
- QEMU

## Usage

To run the kernel in QEMU, run: 
```bash
zig build -fqemu
```

To run the kernel in QEMU with GDB, run:
```bash
zig build -fqemu -Dgdb
```
For GDB, you'll need `gdb-multiarch`.
Then you can run `gdb-multiarch -x ./.gdbinit.tmpl-riscv`.

## Adding a User Program

Simply add a C or Zig file that has a `main` to the `src/user/` folder.
Then add it to the `user_progs` array in `build.zig`. 
```zig
const user_progs = [_]Prog{
    .{ .type = <YOUR PROGRAM LANGUAGE>, .name = <YOUR PROGRAM NAME> }, // <- new program
    .{ .type = .zig, .name = "pbz" },
    .{ .type = .c, .name = "pb" },
    ...
};
```
See the user programs pb ([C source](https://github.com/candrewlee14/xv6-riscv-zig/blob/main/src/user/pb.c)) vs. pbz ([Zig source](https://github.com/candrewlee14/xv6-riscv-zig/blob/main/src/user/pbz.zig)) for examples. 

---

## Original README

xv6 is a re-implementation of Dennis Ritchie's and Ken Thompson's Unix
Version 6 (v6).  xv6 loosely follows the structure and style of v6,
but is implemented for a modern RISC-V multiprocessor using ANSI C.

ACKNOWLEDGMENTS

xv6 is inspired by John Lions's Commentary on UNIX 6th Edition (Peer
to Peer Communications; ISBN: 1-57398-013-7; 1st edition (June 14,
2000)).  See also https://pdos.csail.mit.edu/6.1810/, which provides
pointers to on-line resources for v6.

The following people have made contributions: Russ Cox (context switching,
locking), Cliff Frey (MP), Xiao Yu (MP), Nickolai Zeldovich, and Austin
Clements.

We are also grateful for the bug reports and patches contributed by
Takahiro Aoyagi, Silas Boyd-Wickizer, Anton Burtsev, carlclone, Ian
Chen, Dan Cross, Cody Cutler, Mike CAT, Tej Chajed, Asami Doi,
eyalz800, Nelson Elhage, Saar Ettinger, Alice Ferrazzi, Nathaniel
Filardo, flespark, Peter Froehlich, Yakir Goaron, Shivam Handa, Matt
Harvey, Bryan Henry, jaichenhengjie, Jim Huang, Matúš Jókay, John
Jolly, Alexander Kapshuk, Anders Kaseorg, kehao95, Wolfgang Keller,
Jungwoo Kim, Jonathan Kimmitt, Eddie Kohler, Vadim Kolontsov, Austin
Liew, l0stman, Pavan Maddamsetti, Imbar Marinescu, Yandong Mao, Matan
Shabtay, Hitoshi Mitake, Carmi Merimovich, Mark Morrissey, mtasm, Joel
Nider, Hayato Ohhashi, OptimisticSide, Harry Porter, Greg Price, Jude
Rich, segfault, Ayan Shafqat, Eldar Sehayek, Yongming Shen, Fumiya
Shigemitsu, Cam Tenny, tyfkda, Warren Toomey, Stephen Tu, Rafael Ubal,
Amane Uehara, Pablo Ventura, Xi Wang, WaheedHafez, Keiichi Watanabe,
Nicolas Wolovick, wxdao, Grant Wu, Jindong Zhang, Icenowy Zheng,
ZhUyU1997, and Zou Chang Wei.


The code in the files that constitute xv6 is
Copyright 2006-2022 Frans Kaashoek, Robert Morris, and Russ Cox.

ERROR REPORTS

Please send errors and suggestions to Frans Kaashoek and Robert Morris
(kaashoek,rtm@mit.edu).  The main purpose of xv6 is as a teaching
operating system for MIT's 6.1810, so we are more interested in
simplifications and clarifications than new features.

BUILDING AND RUNNING XV6

You will need a RISC-V "newlib" tool chain from
https://github.com/riscv/riscv-gnu-toolchain, and qemu compiled for
riscv64-softmmu.  Once they are installed, and in your shell
search path, you can run "make qemu".
