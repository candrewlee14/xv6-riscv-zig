// Much of this code comes from https://github.com/binarycraft007/xv6-riscv-zig
const c = @cImport({
    @cInclude("kernel/types.h");
    @cInclude("kernel/param.h");
    @cInclude("kernel/memlayout.h");
    @cInclude("kernel/riscv.h");
    @cInclude("kernel/defs.h");
});
const std = @import("std");
const assert = std.debug.assert;
const Atomic = std.atomic.Atomic;
const riscv = @import("common").riscv;

const c_spinlock = extern struct {
    locked: u32 = 0, // Is the lock held?
    name: ?[*:0]const u8 = null,
    cpu: ?*c.struct_cpu = null,
};

pub const SpinLock = extern struct {
    const Self = @This();
    lock: c_spinlock,

    pub fn init(self: *Self, name: ?[*:0]const u8) void {
        c.initlock(@ptrCast(&self.lock), @constCast(@ptrCast(name)));
    }
    pub fn acquire(self: *SpinLock) void {
        c.acquire(@ptrCast(&self.lock));
    }
    pub fn release(self: *SpinLock) void {
        c.release(@ptrCast(&self.lock));
    }
    pub fn holding(self: *SpinLock) bool {
        return c.holding(@ptrCast(&self.lock)) == 1;
    }
};
