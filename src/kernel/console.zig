const std = @import("std");
const ascii = std.ascii;
const c = @cImport({
    @cInclude("kernel/types.h");
    @cInclude("kernel/param.h");
    @cInclude("kernel/spinlock.h");
    @cInclude("kernel/sleeplock.h");
    @cInclude("kernel/fs.h");
    @cInclude("kernel/file.h");
    @cInclude("kernel/memlayout.h");
    @cInclude("kernel/riscv.h");
    @cInclude("kernel/defs.h");
    @cInclude("kernel/proc.h");
});

const Proc = @import("Proc.zig");
const uart = @import("uart.zig");
const SpinLock = @import("SpinLock.zig");

const BUF_SIZE = 128;
const BACKSPACE = 0x100;

var lock: SpinLock = SpinLock{};

// input
var buf: [BUF_SIZE]u8 = [_]u8{0} ** BUF_SIZE;
var read_idx: u32 = 0; // Read index
var write_idx: u32 = 0; // Write index
var edit_idx: u32 = 0; // Edit index

extern fn consoleread(user_dst: c_int, dst: usize, n: c_int) c_int;
extern fn consolewrite(user_src: c_int, src: usize, n: c_int) c_int;

pub fn init() void {
    uart.init();

    //c.devsw[c.CONSOLE].read = consoleread;
    //c.devsw[c.CONSOLE].write = consolewrite;
    // ToDo: implemente console.read, console.write
    // connect read and write system calls
    // to consoleread and consolewrite.
    //devsw[CONSOLE].read = cons.read;
    //devsw[CONSOLE].write = cons.write;
}

/// send one character to the uart.
/// called by printf(), and to echo input characters,
/// but not from write().
pub fn writeByte(byte: u8) void {
    if (byte == BACKSPACE) {
        // if the user typed backspace, overwrite with a space.
        uart.putcSync(ascii.control_code.bs);
        uart.putcSync(' ');
        uart.putcSync(ascii.control_code.bs);
    } else {
        uart.putcSync(byte);
    }
}

pub fn writeBytes(bytes: []const u8) void {
    for (bytes) |byte| writeByte(byte);
}

/// the console input interrupt handler.
/// uartintr() calls this for input character.
/// do erase/kill processing, append to cons.buf,
/// wake up consoleread() if a whole line has arrived.
pub fn intr(char: u8) void {
    lock.acquire();

    switch (char) {
        'P' => Proc.dump(),
        'U' => // Kill line.
        while (edit_idx != write_idx and
            buf[(edit_idx - 1) % BUF_SIZE] != '\n')
        {
            edit_idx -= 1;
            writeByte(BACKSPACE);
        },
        'H', '\x7f' => {
            if (edit_idx != write_idx) {
                edit_idx -= 1;
                writeByte(BACKSPACE);
            }
        },
        else => if (char != 0 and edit_idx - read_idx < BUF_SIZE) {
            char = if (char == '\r') '\n' else char;

            // echo back to the user.
            writeByte(char);

            // store for consumption by consoleread().
            buf[edit_idx % BUF_SIZE] = char;
            edit_idx += 1;

            if (char == '\n' or char == control('D') or
                edit_idx - read_idx == BUF_SIZE)
            {
                // wake up consoleread() if a whole line (or end-of-file)
                // has arrived.
                write_idx = edit_idx;
                Proc.wakeup(&read_idx);
            }
        },
    }
    lock.release();
}

fn control(char: u8) u8 {
    return char - '@';
}
