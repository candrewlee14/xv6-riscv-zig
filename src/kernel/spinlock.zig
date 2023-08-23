const std = @import("std");
const assert = std.debug.assert;
const Atomic = std.atomic.Atomic;
const riscv = @import("riscv.zig");
const Proc = @import("Proc.zig");
const Cpu = @import("Cpu.zig");
const lock_log = std.log.scoped(.spinlock);
// Mutual exclusion lock.
lock: Atomic(bool) = Atomic(bool).init(false), // Is the lock held?
// For debugging:
cpu: *Cpu = undefined, // The cpu holding the lock.

const SpinLock = @This();

pub fn init() SpinLock {
    return SpinLock{
        .lock = Atomic(bool).init(false),
        .cpu = undefined,
    };
}

/// Acquire the lock.
/// Loops (spins) until the lock is acquired.
pub fn acquire(self: *SpinLock) void {
    @setRuntimeSafety(false);
    pushOff(); // disable interrupts to avoid deadlock.

    if (self.holding()) @panic("acquire");

    // On RISC-V, tryCompareAndSwap turns into an atomic swap:
    //   a5 = 1
    //   s1 = &self.locked
    //   amoswap.w.aq a5, a5, (s1)
    while (self.lock.tryCompareAndSwap(false, true, .Acquire, .Acquire) == true) {}

    // Tell the zig compiler and the processor to not move loads or stores
    // past this point, to ensure that the critical section's memory
    // references happen strictly after the lock is acquired.
    // On RISC-V, this emits a fence instruction.
    @fence(.SeqCst);

    self.cpu = Proc.myCpu();
}

/// Release the lock.
pub fn release(self: *SpinLock) void {
    @setRuntimeSafety(false);
    if (!self.holding()) @panic("release");
    self.cpu = undefined;

    // Tell the zig compiler and the CPU to not move loads or stores
    // past this point, to ensure that all the stores in the critical
    // section are visible to other CPUs before the lock is released,
    // and that loads in the critical section occur strictly before
    // the lock is released.
    // On RISC-V, this emits a fence instruction.
    @fence(.SeqCst);

    // Release the lock, equivalent to self.locked = false.
    // This code doesn't use a C assignment, since the C standard
    // implies that an assignment might be implemented with
    // multiple store instructions.
    // On RISC-V, sync_lock_release turns into an atomic swap:
    //   s1 = &self.locked
    //   amoswap.w zero, zero, (s1)
    self.lock.store(false, .Release);
    popOff();
}

pub fn holding(self: *SpinLock) bool {
    @setRuntimeSafety(false);
    return self.lock.load(.Unordered) and self.cpu == Proc.myCpu();
}

pub fn pushOff() void {
    @setRuntimeSafety(false);
    var old = riscv.intr_get();

    riscv.intr_off();

    if (Proc.myCpu().noff == 0)
        Proc.myCpu().intena = old;

    Proc.myCpu().noff += 1;
}

pub fn popOff() void {
    @setRuntimeSafety(false);
    var cpu = Proc.myCpu();

    if (riscv.intr_get())
        @panic("pop_off - interruptible");

    if (cpu.noff < 1)
        @panic("pop_off");

    cpu.noff -= 1;
    if (cpu.noff == 0 and cpu.intena)
        riscv.intr_on();
}
