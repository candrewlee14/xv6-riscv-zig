const c = @cImport({
    @cInclude("kernel/types.h");
    @cInclude("kernel/param.h");
    @cInclude("kernel/memlayout.h");
    @cInclude("kernel/riscv.h");
    @cInclude("kernel/defs.h");
});
const std = @import("std");
const log_root = @import("log.zig");
const riscv = @import("common").riscv;
const Proc = @import("Proc.zig");
const Atomic = std.atomic.Atomic;
const kalloc = @import("kalloc.zig");

const log = std.log.scoped(.kmain);

var started = Atomic(bool).init(false);

pub fn kmain() void {
    if (Proc.cpuId() == 0) {
        c.consoleinit();
        log.info("xv6 kernel is booting", .{});
        kalloc.kinit(); // set up allocator (zig)
        c.kvminit(); // create kernel page table
        c.kvminithart(); // turn on paging
        c.procinit(); // process table
        c.trapinit(); // trap vectors
        c.trapinithart(); // install kernel trap vector
        c.plicinit(); // set up interrupt controller
        c.plicinithart(); // ask PLIC for device interrupts
        c.binit(); // buffer cache
        c.iinit(); // inode table
        c.fileinit(); // file table
        c.virtio_disk_init(); // emulated hard disk
        c.userinit(); // first user process
        started.store(true, .SeqCst);
    } else {
        while (!started.load(.SeqCst)) {}

        log.info("hart {d} starting", .{Proc.cpuId()});
        c.kvminithart(); // turn on paging
        c.trapinithart(); // install kernel trap vector
        c.plicinithart(); // ask PLIC for device interrupts
    }
    c.scheduler();
}

// overrides the root page allocator
pub const os = struct {
    heap: struct {
        page_allocator: std.mem.Allocator = kalloc.page_allocator,
    },
};
