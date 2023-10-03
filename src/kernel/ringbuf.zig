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
const Book = com.ringbuf.Book;
const MagicBuf = com.ringbuf.MagicBuf;
const Rb = com.ringbuf;

// we expose these in common because they will be used by the user lib
const RINGBUF_SIZE = com.ringbuf.RINGBUF_SIZE;
const MAX_NAME_LEN = com.ringbuf.MAX_NAME_LEN;
const MAX_RINGBUFS = com.ringbuf.MAX_RINGBUFS;

const RingbufManager = @This();

/// Global spinlock to protect the ringbuf's array
var spinlock: SpinLock = SpinLock.init();
/// Global array of ringbufs
var ringbufs: [MAX_RINGBUFS]Ringbuf = [_]Ringbuf{.{}} ** MAX_RINGBUFS;

/// Set up ringbuf manager
pub fn init() void {
    // we do nothing here, because the spinlock and ringbufs are already initialized with defaults.
    // but we use it from main because
    // we want the code in this file not to be tree-shaken away by the Zig compiler.
    return;
}

const Owner = extern struct {
    proc: ?*c.struct_proc = null,
    vbuf: ?MagicBuf = null,
    vbook: ?PagePtr = null,
};

const Ringbuf = extern struct {
    const Self = @This();

    refcount: u32 = 0,
    owners: [2]Owner = [_]Owner{.{}} ** 2,
    name_buf: [MAX_NAME_LEN]u8 = [_]u8{0} ** MAX_NAME_LEN,
    buf_pages: [RINGBUF_SIZE]?PagePtr = [_]?PagePtr{null} ** 16,
    book_page: ?PagePtr = null,

    /// Activates this ringbuf
    /// Refcount should be 0 (deactivated)
    /// Must be holding the lock
    pub fn activate(self: *Self, name: []const u8) !void {
        if (self.refcount > 0) return error.AlreadyActive;
        if (name.len > MAX_NAME_LEN or name.len == 0) return error.BadNameLength;
        @memcpy(&self.name_buf, name);

        // allocate all the buf pages
        const alloced_page_count = blk: {
            for (&self.buf_pages, 0..) |*buf_pg_ptr, i| {
                const page = kalloc.allocPage() orelse break :blk i;
                buf_pg_ptr.* = page;
            }
            break :blk self.buf_pages.len;
        };
        self.book_page = kalloc.allocPage();
        // undo all allocations if we failed to allocate any of the pages
        if (alloced_page_count < self.buf_pages.len or self.book_page == null) {
            if (self.book_page != null) {
                kalloc.freePage(self.book_page.?) catch @panic("failed to free page");
                self.book_page = null;
            }
            for (self.buf_pages[0..alloced_page_count]) |*buf_pg_ptr| {
                const buf: PagePtr = buf_pg_ptr.*.?;
                kalloc.freePage(buf) catch @panic("failed to free page");
                buf_pg_ptr.* = null;
            }
            return error.OutOfMemory;
        } else {
            // set up bookkeeping
            const book_p: *Book = @ptrCast(self.book_page.?);
            book_p.* = .{};
        }
    }
    /// Deactivates this ring buffer and frees its resources
    /// Must be holding a lock
    pub fn deactivate(self: *Self) void {
        for (&self.buf_pages) |*pg_o_p| {
            if (pg_o_p.*) |pg| {
                kalloc.freePage(pg) catch @panic("failed to free page");
                pg_o_p.* = null;
            }
        }
        if (self.book_page == null) @panic("deactivate: book page is already null");
        const book_p: *Book = @ptrCast(self.book_page.?);
        book_p.* = .{};
        kalloc.freePage(self.book_page.?) catch @panic("failed to free page");
        if (self.owners[0].proc != null or self.owners[1].proc != null) @panic("ringbuf has owners");
        self.* = .{};
    }

    /// Disowns a ringbuf from a process
    /// If the ringbuf is not owned by the process, do nothing
    /// Decrements the refcount and deactivates the ringbuf if the refcount is 0
    pub fn disownIfOwned(self: *Self, proc: *c.struct_proc) void {
        const owner: *Owner = brk: {
            if (self.owners[0].proc == proc) {
                break :brk &self.owners[0];
            } else if (self.owners[1].proc == proc) {
                break :brk &self.owners[1];
            } else {
                return;
            }
        };
        owner.proc = null;
        if (owner.vbuf) |vbuf| {
            c.uvmunmap(proc.pagetable, @intFromPtr(vbuf), vbuf.len / riscv.PGSIZE, 0);
            owner.vbuf = null;
        } else @panic("disowning a ringbuf without a vbuf");
        if (owner.vbook) |vbook_p| {
            c.uvmunmap(proc.pagetable, @intFromPtr(vbook_p), 1, 0);
            owner.vbuf = null;
        } else @panic("disowning a ringbuf without a vbook");
        self.refcount -= 1;
        proc.owned_ringbufs -= 1;
        // we choose to free the physical memory in deactivate, not in uvmunmap
        if (self.refcount == 0) self.deactivate();
    }
};

fn findFreeRingbuf() ?*Ringbuf {
    for (&ringbufs) |*rb| {
        if (rb.refcount == 0) return rb;
    }
    return null;
}

fn findRingbufByName(name: []const u8) ?*Ringbuf {
    for (&ringbufs) |*rb| {
        if (rb.refcount == 0) continue;
        const name_str: [*:0]const u8 = @ptrCast(&rb.name_buf);
        const rb_name = std.mem.span(name_str);
        if (std.mem.eql(u8, name, rb_name)) return rb;
    }
    return null;
}

/// Ringbuf system call
/// - name_str: name of the ringbuf
/// - op: open or close
/// - addr_va: pointer to the address of the ringbuf.
///   On open, the address of the ringbuf is written out.
///   On close, the address of the ringbuf is read in.
///
///  We use the process's top_free_uvm_pg to find a slot in the userspace.
///  We map the ringbuf twice contiguously, and the book page right under it.
fn ringbuf(name_str: [*:0]const u8, op: Rb.Op, addr_va: *?*align(riscv.PGSIZE) anyopaque) Rb.RingbufError!void {
    spinlock.acquire();
    defer spinlock.release();

    const name: []const u8 = std.mem.span(name_str);
    if (name.len > MAX_NAME_LEN or name.len == 0) return error.BadNameLength;

    var proc: *c.struct_proc = c.myproc() orelse @panic("myproc is null");

    switch (op) {
        .open => {
            // find the named ringbuf or activate a free slot
            var owner: *Owner = undefined;
            const rb: *Ringbuf = blk: {
                if (findRingbufByName(name)) |rb| {
                    if (rb.refcount == 0) @panic("inactive ringbuf found by name");
                    const owner_count = blk2: {
                        var oc: u8 = 0;
                        for (&rb.owners) |o| {
                            if (o.proc) |p| {
                                oc += 1;
                                if (p == proc) return error.AlreadyIsOwner;
                            }
                        }
                        break :blk2 oc;
                    };
                    if (owner_count == 0) @panic("orphaned ringbuf found by name");
                    if (owner_count == 2) return error.AlreadyTwoOwners;

                    owner = if (rb.owners[1].proc == null) &rb.owners[1] else &rb.owners[0];
                    break :blk rb;
                } else if (findFreeRingbuf()) |rb| {
                    try rb.activate(name);
                    if (rb.owners[0].proc != null or rb.owners[1].proc != null) @panic("free ringbuf should not have any owners");
                    owner = &rb.owners[0];
                    break :blk rb;
                } else {
                    return error.NoFreeRingbuf;
                }
            };
            owner.proc = proc;
            proc.owned_ringbufs += 1;
            rb.refcount += 1;
            errdefer {
                owner.proc = null;
                rb.refcount -= 1;
                rb.deactivate();
            }
            // map all physical pages into the process twice contiguously
            const perm = c.PTE_R | c.PTE_W | c.PTE_U;
            for (0..2) |_| {
                for (&rb.buf_pages) |pg| {
                    // TODO: undo all mappings if we fail to map a page
                    if (pg == null) @panic("buf page is null");
                    if (0 > c.mappages(
                        proc.pagetable,
                        proc.top_free_uvm_pg,
                        riscv.PGSIZE,
                        @intFromPtr(pg),
                        perm,
                    )) return error.MapPagesFailed;
                    proc.top_free_uvm_pg -= riscv.PGSIZE;
                }
            }
            // map the book page right under the ringbuf
            if (rb.book_page == null) @panic("book page is null");
            if (0 > c.mappages(
                proc.pagetable,
                proc.top_free_uvm_pg,
                riscv.PGSIZE,
                @intFromPtr(rb.book_page.?),
                perm,
            )) return error.MapPagesFailed;
            proc.top_free_uvm_pg -= riscv.PGSIZE;
            // | btm of ringbuf    |
            // | book              |
            // | top_free_uvm_pg   |
            const book_vaddr = proc.top_free_uvm_pg + 1 * riscv.PGSIZE;
            var ringbuf_loc = proc.top_free_uvm_pg + 2 * riscv.PGSIZE;
            // store the mapped addresses
            owner.vbook = @ptrFromInt(book_vaddr);
            owner.vbuf = @ptrFromInt(ringbuf_loc);

            // copy the address of the ringbuf into userspace
            // TODO: undo everything if we fail to copyout
            if (0 > c.copyout(
                proc.pagetable,
                @intFromPtr(addr_va), // store the ringbuf user address here
                @intFromPtr(&ringbuf_loc), // copy from this kernel address (which holds the virtual address of the ringbuf)
                @sizeOf(*anyopaque),
            )) return error.CopyOutFailed;
            // leave a guard page
            proc.top_free_uvm_pg -= riscv.PGSIZE;
        },
        .close => {
            var vaddr: ?*anyopaque = null;
            // copy the address of the ringbuf into kernel space
            if (0 > c.copyin(
                proc.pagetable,
                @ptrCast(&vaddr), // store the ringbuf user address here
                @intFromPtr(addr_va), // copy from the given user address of the ringbuf user address
                @sizeOf(?*anyopaque),
            )) return error.CopyInFailed;
            const ringbuf_vaddr: usize = @intFromPtr(vaddr orelse return error.NoAddrGiven);

            const rb = findRingbufByName(name) orelse return error.NameNotFound;

            const owner: *Owner = blk: {
                if (proc == rb.owners[0].proc) {
                    break :blk &rb.owners[0];
                } else if (proc == rb.owners[1].proc) {
                    break :blk &rb.owners[1];
                } else return error.NotOwner;
            };
            const vbuf_u: usize = @intFromPtr(owner.vbuf);
            const vbook_u: usize = @intFromPtr(owner.vbook);
            if (vbuf_u != ringbuf_vaddr) return error.BadAddr;
            if (vbook_u != ringbuf_vaddr - riscv.PGSIZE) return error.BadAddr;

            if (rb.refcount == 0) return error.AlreadyInactive;
            if (rb.book_page == null) @panic("book page is null");

            // disown the ringbuf from the process
            // disown also unmaps the pages and frees the physical memory if the refcount is 0
            rb.disownIfOwned(proc);

            // To help us avoid *some* fragmentation for the top_free_uvm_pg,
            // we'll bump up the top_free_uvm_pg if this is the lowest ringbuf.
            // | guard page        | <- new proc.top_free_uvm_pg
            //  ....   rb.buf_pages.len * 2 pages
            // | btm of ringbuf    | <- ringbuf_vaddr
            // | book              |
            // | guard pg          |
            // | top_free_uvm_pg   | <- old proc.top_free_uvm_pg
            if (proc.top_free_uvm_pg == ringbuf_vaddr - 3 * riscv.PGSIZE) {
                // move up by guard page + book + double mapped ringbuf
                proc.top_free_uvm_pg += (1 + 1 + 2 * rb.buf_pages.len) * riscv.PGSIZE;
            }
        },
    }
}

export fn sys_ringbuf() c.uint64 {
    c.begin_op();
    defer c.end_op();

    var name: [MAX_NAME_LEN]u8 = [_]u8{0} ** MAX_NAME_LEN;
    if (0 > c.argstr(0, &name, MAX_NAME_LEN)) {
        // sys_FOO C functions return a uint64 yet return -1 on errors
        // Zig has stricter rules about implicit casts + overflow and underflow,
        // so we'll need to return a bitcasted negative on errors
        return @bitCast(-@as(isize, @intFromError(error.BadNameLength)));
    }
    const name_str: [*:0]const u8 = @ptrCast(&name);

    var open: c_int = -1;
    c.argint(1, &open);

    var null_ptr: ?*anyopaque = null;
    var addr: *?*anyopaque = &null_ptr;
    c.argaddr(2, @ptrCast(&addr));

    ringbuf(name_str, @enumFromInt(open), @ptrCast(addr)) catch |err| {
        return @bitCast(-@as(isize, @intFromError(err)));
    };
    return 0;
}

fn find_owned_ringbuf(proc: *c.struct_proc) ?*Ringbuf {
    for (&ringbufs) |*rb| {
        if (rb.refcount > 0) {
            if (rb.owners[0].proc == proc or rb.owners[1].proc == proc) return rb;
        }
    }
    return null;
}

export fn ringbuf_disown_all(proc: *c.struct_proc) void {
    spinlock.acquire();
    defer spinlock.release();
    for (&ringbufs) |*rb| {
        rb.disownIfOwned(proc);
    }
}
