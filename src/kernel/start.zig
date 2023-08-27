const std = @import("std");
const riscv = @import("riscv.zig");
const main = @import("main.zig");
const param = @import("param.zig");
const memlayout = @import("memlayout.zig");
const log_root = @import("log.zig");

// a scratch area per CPU for machine-mode timer interrupts.
var timer_scratch: [param.NCPU][5]usize = undefined;

// entry.S needs one stack per CPU.
const stack_size: usize = 4096 * param.NCPU;

// assembly code in kernelvec.S for machine-mode timer interrupt.
extern fn timervec(...) void;

// entry.S needs one stack per CPU.
export var stack0 align(16) = [_]u8{0} ** stack_size;

/// entry.S jumps here in machine mode on stack0.
pub export fn start() void {
    // set M Previous Privilege mode to Supervisor, for mret.
    var mstatus = riscv.r_mstatus();
    mstatus &= ~@as(usize, riscv.MSTATUS_MPP_MASK);
    mstatus |= @intFromEnum(riscv.MSTATUS.MPP_S);
    riscv.w_mstatus(mstatus);

    // set M Exception Program Counter to kmain, for mret.
    // requires code_model = .medium
    riscv.w_mepc(@intFromPtr(&main.kmain));

    // disable paging for now.
    riscv.w_satp(0);

    // delegate all interrupts and exceptions to supervisor mode.
    riscv.w_medeleg(@as(usize, 0xffff));
    riscv.w_mideleg(@as(usize, 0xffff));
    riscv.w_sie(riscv.r_sie() |
        @intFromEnum(riscv.SIE.SEIE) |
        @intFromEnum(riscv.SIE.STIE) |
        @intFromEnum(riscv.SIE.SSIE));

    // configure Physical Memory Protection to give supervisor mode
    // access to all of physical memory.
    riscv.w_pmpaddr0(@as(usize, 0x3fffffffffffff));
    riscv.w_pmpcfg0(@as(usize, 0xf));

    // ask for clock interrupts.
    timerinit();

    // keep each CPU's hartid in its tp register, for cpuid().
    const id = riscv.r_mhartid();
    riscv.w_tp(id);

    asm volatile ("mret");
}

/// arrange to receive timer interrupts.
/// they will arrive in machine mode at
/// at timervec in kernelvec.S,
/// which turns them into software interrupts for
/// devintr() in trap.c.
pub fn timerinit() void {
    // each CPU has a separate source of timer interrupts.
    const id = riscv.r_mhartid();

    // ask the CLINT for a timer interrupt.
    const interval = 1000000; // cycles; about 1/10th second in qemu.
    memlayout.CLINT_MTIMECMP(id).* = memlayout.CLINT_MTIME.* + interval;

    // prepare information in scratch[] for timervec.
    // scratch[0..2] : space for timervec to save registers.
    // scratch[3] : address of CLINT MTIMECMP register.
    // scratch[4] : desired interval (in cycles) between timer interrupts.
    var scratch = timer_scratch[id];
    scratch[3] = @intFromPtr(memlayout.CLINT_MTIMECMP(id));
    scratch[4] = interval;
    riscv.w_mscratch(@intFromPtr(&scratch));

    // set the machine-mode trap handler.
    riscv.w_mtvec(@intFromPtr(&timervec));

    // enable machine-mode interrupts.
    riscv.w_mstatus(riscv.r_mstatus() | @intFromEnum(riscv.MSTATUS.MIE));

    // enable machine-mode timer interrupts.
    riscv.w_mie(riscv.r_mie() | @intFromEnum(riscv.MIE.MTIE));
}

pub fn panic(
    msg: []const u8,
    error_return_trace: ?*std.builtin.StackTrace,
    _: ?usize,
) noreturn {
    @setCold(true);
    _ = error_return_trace;
    const panic_log = std.log.scoped(.panic);
    log_root.locking = false;
    panic_log.err("{s}\n", .{msg});
    log_root.panicked = true; // freeze uart output from other CPUs
    while (true) {}
}

pub const std_options = struct {
    // Set the log level to info
    pub const log_level = .debug;

    // Define logFn to override the std implementation
    pub const logFn = log_root.klogFn;
};
