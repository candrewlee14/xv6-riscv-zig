const std = @import("std");
const riscv = @import("riscv.zig");
const memlayout = @import("memlayout.zig");
const SpinLock = @import("SpinLock.zig");
const Queue = @import("queue.zig").Queue;
const Stack = std.atomic.Stack;
const kalloc_log = std.log.scoped(.kalloc);
const mem = std.mem;

extern var end: u8;

const Page = struct {
    next: ?*Page = null,
};

var lock: SpinLock = SpinLock{};
var free_pages: Queue(Page) = .{ .name = "page list" };

pub fn init() void {
    var start = mem.alignForward(usize, @intFromPtr(&end), mem.page_size);
    var ptr: [*]u8 align(mem.page_size) = @alignCast(@as([*]u8, @ptrFromInt(start)));
    kalloc_log.debug(
        "available [0x{x} - 0x{x}]\n",
        .{ start, memlayout.PHYSTOP },
    );
    kalloc_log.debug("start init kernel page allocator\n", .{});
    freePages(ptr[0..(memlayout.PHYSTOP - start)]);
    kalloc_log.debug("init kernel page allocator success\n", .{});
}

pub fn freePages(pages: []u8) void {
    var i: usize = 0;
    while ((i + 4096) <= pages.len) : (i += 4096) {
        freePage(pages[i..].ptr[0..riscv.PGSIZE]);
    }
}

/// Free the page of physical memory pointed at by start,
/// which normally should have been returned by a
/// call to kalloc().  (The exception is when
/// initializing the allocator; see kinit above.)
pub fn freePage(page: []u8) void {
    const addr = @intFromPtr(&page[0]);

    if (!mem.isAligned(addr, riscv.PGSIZE))
        @panic("not aligned");
    if (addr < @intFromPtr(&end))
        @panic("forbit to free kernel mem");
    if (addr >= memlayout.PHYSTOP)
        @panic("invalid addr to free");

    @memset(page[0..riscv.PGSIZE], 1);

    lock.acquire();
    free_pages.push(@as(*Page, @alignCast(@ptrCast(page.ptr))));
    lock.release();
}

/// Allocate one 4096-byte page of physical memory.
/// Returns a pointer that the kernel can use.
/// Returns error if the memory cannot be allocated.
pub fn allocPage() ![]u8 {
    var page: []u8 = undefined;
    page.len = riscv.PGSIZE;

    lock.acquire();
    if (free_pages.pop()) |p| {
        page.ptr = @as([*]u8, @ptrCast(p));
    } else {
        lock.release();
        return error.KallocFailed;
    }
    lock.release();

    @memset(page, 5);
    return page;
}

/// wrapper for allocPage used by c code
pub export fn kalloc() ?*anyopaque {
    var slice = allocPage() catch return null;
    return slice.ptr;
}

/// wrapper for freePage used by c code
pub export fn kfree(pa: ?*anyopaque) void {
    var slice = @as([*]u8, @ptrCast(pa))[0..riscv.PGSIZE];
    freePage(slice);
}
