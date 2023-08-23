const c = @cImport({
    @cInclude("kernel/types.h");
    @cInclude("kernel/param.h");
    @cInclude("kernel/memlayout.h");
    @cInclude("kernel/riscv.h");
    @cInclude("kernel/defs.h");
});
const std = @import("std");
const log_root = @import("log.zig");
const kmain_log = std.log.scoped(.kmain);
const riscv = @import("riscv.zig");
const kalloc = @import("kalloc.zig");
const kvm = @import("kvm.zig");
const console = @import("console.zig");
const Proc = @import("Proc.zig");
const Atomic = std.atomic.Atomic;

var started = Atomic(bool).init(false);

pub fn kmain() void {
    if (Proc.cpuId() == 0) {
        console.init();
        c.consoleinit(); // one init step is not implementated in zig
        kmain_log.info("xv6 kernel is booting", .{});
        kmain_log.info("kalloc", .{});
        kalloc.init(); // physical page allocator
        // c.kinit();

        kmain_log.info("kvminit", .{});
        c.kvminit();
        c.kvminithart();
        // kvm.init(); // create kernel page table
        // kvm.initHart(); // turn on paging
        kmain_log.info("procinit", .{});
        c.procinit(); // process table
        kmain_log.info("trapinit", .{});
        c.trapinit(); // trap vectors
        kmain_log.info("trapinithart", .{});
        c.trapinithart(); // install kernel trap vector
        kmain_log.info("plicinit", .{});
        c.plicinit(); // set up interrupt controller
        kmain_log.info("plicinithart", .{});
        c.plicinithart(); // ask PLIC for device interrupts
        kmain_log.info("binit", .{});
        c.binit(); // buffer cache
        kmain_log.info("iinit", .{});
        c.iinit(); // inode table
        kmain_log.info("fileinit", .{});
        c.fileinit(); // file table
        kmain_log.info("virtio_disk_init", .{});
        c.virtio_disk_init(); // emulated hard disk
        kmain_log.info("userinit", .{});
        c.userinit(); // first user process
        started.store(true, .SeqCst);
    } else {
        while (!started.load(.SeqCst)) {}

        kmain_log.info("hart {d} starting", .{Proc.cpuId()});
        kvm.initHart(); // turn on paging
        c.trapinithart(); // install kernel trap vector
        c.plicinithart(); // ask PLIC for device interrupts
    }
    c.scheduler();
}
