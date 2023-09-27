const std = @import("std");
const c = @cImport({
    @cInclude("kernel/types.h");
    @cInclude("kernel/param.h");
    @cInclude("kernel/memlayout.h");
    @cInclude("kernel/riscv.h");
    @cInclude("kernel/defs.h");
    @cInclude("kernel/spinlock.h");
    @cInclude("kernel/proc.h");
});
const com = @import("common");
const riscv = com.riscv;
const SpinLock = @import("spinlock.zig");
const kalloc = @import("kalloc.zig");
const PagePtr = kalloc.PagePtr;

const Op = enum(u1) {
    open = 1,
    close = 0,
};

const MAX_RINGBUFS = 10;
const RINGBUF_SIZE = 16;

const RingbufManager = @This();

var spinlock: SpinLock = SpinLock.init();
var ringbufs: [MAX_RINGBUFS]Ringbuf = [_]Ringbuf{.{}} ** MAX_RINGBUFS;

pub fn init() void {
    return;
}

const MAX_NAME_LEN = 16;

const Ringbuf = extern struct {
    const Self = @This();
    refcount: u32 = 0,
    name_buf: [MAX_NAME_LEN]u8 = undefined,
    name: ?[]const u8 = null,
    buf_pages: [RINGBUF_SIZE]?PagePtr = [_]?PagePtr{null} ** 16,
    book_page: ?PagePtr = null,

    /// Activates this ringbuf
    /// Refcount should be 0 (deactivated)
    /// Must be holding the lock
    pub fn activate(self: *Self, name: []const u8) !void {
        if (self.refcount > 0) return error.AlreadyActive;
        if (name.len > MAX_NAME_LEN or name.len == 0) {
            return error.BadNameLength;
        }
        @memcpy(self.name_buf, name);
        self.name = self.name_buf[0..name.len];
        errdefer self.name = null;

        const alloced_page_count = blk: {
            for (&self.buf_pages, 0..) |*buf_pg_ptr, i| {
                const page = kalloc.allocPage() orelse break :blk i;
                buf_pg_ptr.* = page;
            }
            break :blk self.buf_pages.len;
        };
        self.book_page = kalloc.allocPage();
        if (alloced_page_count < self.buf_pages.len or self.book_page == null) {
            for (&self.buf_pages[0..alloced_page_count]) |*buf_pg_ptr| {
                const buf: PagePtr = buf_pg_ptr.?;
                kalloc.freePage(buf);
                buf_pg_ptr.* = null;
                return error.OutOfMemory;
            }
        }
    }
    /// Deactivates this ring buffer and frees its resources
    /// Must be holding a lock
    pub fn deactivate(self: *Self) void {
        for (&self.buf_pages) |pg_o| {
            if (pg_o) |pg| {
                kalloc.freePage(pg) catch unreachable;
            }
        }
        kalloc.freePage(self.book_page) catch unreachable;
        self.name = null;
        self.refcount = 0;
    }
};

pub fn findFreeRingbuf() ?*Ringbuf {
    for (&ringbufs) |*rb| {
        if (rb.refcount == 0) return rb;
    }
    return null;
}

pub fn findRingbufByName(name: []const u8) ?*Ringbuf {
    for (&ringbufs) |*rb| {
        if (rb.name) |rb_name| {
            if (std.mem.eql(u8, name, rb_name)) return rb;
        }
    }
    return null;
}

fn ringbuf(name_str: [*:0]const u8, op: Op, addr: **anyopaque) !void {
    _ = addr;
    spinlock.acquire();
    defer spinlock.release();
    const name: []u8 = std.mem.span(name_str);
    if (name.len > MAX_NAME_LEN or name.len == 0) {
        return error.BadNameLength;
    }
    const proc = c.myproc();
    const pagetable = c.proc_pagetable(proc);
    if (op == .open) {
        const rb: *Ringbuf = blk: {
            if (findRingbufByName(name)) |rb| {
                std.debug.assert(rb.refcount > 0);
                break :blk rb;
            } else if (findFreeRingbuf()) |rb| {
                rb.activate();
                break :blk rb;
            } else {
                return error.NoFreeRingbuf;
            }
        };
        rb.refcount += 1;
        const perm = c.PTE_R | c.PTE_W | c.PTE_U;
        for (&rb.buf_pages, 0..) |pg, i| {
            c.mappages(
                pagetable,
                proc.top_free_uvm_page - i * riscv.PGSIZE,
                riscv.PGSIZE,
                @intFromPtr(pg),
                perm,
            );
            // map it again lower
            c.mappages(
                pagetable,
                proc.top_free_uvm_page - (i + rb.buf_pages.len) * riscv.PGSIZE,
                riscv.PGSIZE,
                @intFromPtr(pg),
                perm,
            );
        }
        // TODO: map book somewhere
        proc.top_free_uvm_page -= (2 * rb.buf_pages.len + 1) * riscv.PGSIZE;
    } else if (op == .close) {
        const rb = findRingbufByName(name) orelse return error.NameNotFound;
        rb.refcount -= 1;
        // How do we find where in the userspace this was mapped?
        // TODO: unmap each ringbuf
        // TODO: unmap book
        if (rb.refcount == 0) {
            rb.deactivate();
        }
    }
}

export fn sys_ringbuf() void {
    // TODO: fill this in
}
