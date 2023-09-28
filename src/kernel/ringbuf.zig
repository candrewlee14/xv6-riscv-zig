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

const Ringbuf = struct {
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
        @memcpy(&self.name_buf, name);
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
            for (self.buf_pages[0..alloced_page_count]) |*buf_pg_ptr| {
                const buf: PagePtr = buf_pg_ptr.*.?;
                try kalloc.freePage(buf);
                buf_pg_ptr.* = null;
                return error.OutOfMemory;
            }
        }
    }
    /// Deactivates this ring buffer and frees its resources
    /// Must be holding a lock
    pub fn deactivate(self: *Self) void {
        for (&self.buf_pages) |*pg_o_p| {
            if (pg_o_p.*) |pg| {
                kalloc.freePage(pg) catch unreachable;
                pg_o_p.* = null;
            }
        }
        std.debug.assert(self.book_page != null);
        kalloc.freePage(self.book_page.?) catch unreachable;
        self.book_page = null;
        self.name = null;
        self.name_buf = [_]u8{0} ** MAX_NAME_LEN;
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

fn ringbuf(name_str: [*:0]const u8, op: Op, addr_p: *?*anyopaque) !void {
    spinlock.acquire();
    defer spinlock.release();
    const name: []const u8 = std.mem.span(name_str);
    if (name.len > MAX_NAME_LEN or name.len == 0) {
        return error.BadNameLength;
    }
    var proc: *c.struct_proc = c.myproc() orelse return error.NoProc;
    const pagetable = c.proc_pagetable(proc);
    if (op == .open) {
        const rb: *Ringbuf = blk: {
            if (findRingbufByName(name)) |rb| {
                std.debug.assert(rb.refcount > 0);
                break :blk rb;
            } else if (findFreeRingbuf()) |rb| {
                try rb.activate(name);
                break :blk rb;
            } else {
                return error.NoFreeRingbuf;
            }
        };
        rb.refcount += 1;
        errdefer {
            if (rb.refcount) rb.deactivate();
        }
        const perm = c.PTE_R | c.PTE_W | c.PTE_U;
        for (&rb.buf_pages, 0..) |pg, i| {
            _ = c.mappages(
                pagetable,
                proc.top_free_uvm_page - i * riscv.PGSIZE,
                riscv.PGSIZE,
                @intFromPtr(pg),
                perm,
            );
            // map it again lower
            _ = c.mappages(
                pagetable,
                proc.top_free_uvm_page - (i + rb.buf_pages.len) * riscv.PGSIZE,
                riscv.PGSIZE,
                @intFromPtr(pg),
                perm,
            );
        }
        std.debug.assert(rb.book_page != null);
        _ = c.mappages(
            pagetable,
            proc.top_free_uvm_page - (2 * rb.buf_pages.len + 1) * riscv.PGSIZE,
            riscv.PGSIZE,
            @intFromPtr(rb.book_page.?),
            perm,
        );
        var ringbuf_loc = proc.top_free_uvm_page - rb.buf_pages.len * riscv.PGSIZE;
        // TODO: check for error
        _ = c.copyout(
            pagetable,
            @intFromPtr(addr_p),
            @ptrCast(&ringbuf_loc),
            @sizeOf(*anyopaque),
        );
        // we map the buffer twice, plus the book page and a guard slot
        proc.top_free_uvm_page -= (2 * rb.buf_pages.len + 2) * riscv.PGSIZE;
    } else if (op == .close) {
        var in_addr: ?*anyopaque = null;
        // TODO: handle errors
        _ = c.copyin(
            pagetable,
            @ptrCast(&in_addr),
            @intFromPtr(addr_p),
            @sizeOf(?*anyopaque),
        );
        const vaddr: c.uint64 = @intFromPtr(in_addr orelse return error.NoAddrGiven);
        const rb = findRingbufByName(name) orelse return error.NameNotFound;
        rb.refcount -= 1;
        // we subtract 1 page from addr because that points to the book
        // then we free the whole book/ringbuf at once
        c.uvmunmap(pagetable, vaddr - riscv.PGSIZE, 1 + rb.buf_pages.len, 0);
        // we choose to free the physical memory in deactivate, not in uvmunmap
        if (rb.refcount == 0) rb.deactivate();
    }
}

export fn sys_ringbuf() c.uint64 {
    const neg1: c.uint64 = std.math.maxInt(c.uint64);
    var name: [MAX_NAME_LEN]u8 = [_]u8{0} ** MAX_NAME_LEN;
    c.begin_op();
    defer c.end_op();
    if (0 > c.argstr(0, @ptrCast(&name), MAX_NAME_LEN)) return neg1;
    var open: c_int = -1;
    c.argint(1, &open);
    var addr: *?*anyopaque = undefined;
    c.argaddr(2, @ptrCast(&addr));
    const name_str: [*:0]const u8 = @ptrCast(&name);
    ringbuf(name_str, @enumFromInt(open), addr) catch return neg1;
    return 0;
}
