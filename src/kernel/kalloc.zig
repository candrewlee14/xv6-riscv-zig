const std = @import("std");
const SpinLock = @import("spinlock.zig").SpinLock;
const memlayout = @import("../kernel/memlayout.zig");
const riscv = @import("common").riscv;
const assert = std.debug.assert;
const log = std.log.scoped(.kalloc);

// first address after kernel.
pub const end = @extern([*c]c_char, .{ .name = "end" });

const Block = extern struct {
    next: ?*Block,
};

var lock: SpinLock = undefined;
var freelist: ?*Block = null;

pub export fn kinit() void {
    log.info("setting up page allocator", .{});
    lock.init("kalloc");
    freerange(@ptrCast(end), @ptrFromInt(memlayout.PHYSTOP));
}

pub export fn freerange(pa_start: *anyopaque, pa_end: *anyopaque) void {
    const p_start_offset: usize = @intFromPtr(pa_start);
    var p_offset = std.mem.alignForward(usize, p_start_offset, riscv.PGSIZE);
    const p_end_offset: usize = @intFromPtr(pa_end);
    while (p_offset + riscv.PGSIZE <= p_end_offset) : (p_offset += riscv.PGSIZE) {
        const ptr: [*]u8 = @ptrFromInt(p_offset);
        freePage(@alignCast(ptr[0..riscv.PGSIZE])) catch {
            @panic("freerange error");
        };
    }
}

pub export fn kfree(pa: *anyopaque) void {
    const ptr: [*]u8 = @ptrCast(pa);
    freePage(@alignCast(ptr[0..riscv.PGSIZE])) catch {
        @panic("kfree error");
    };
}

pub export fn kalloc() ?*anyopaque {
    const page_slice_o = allocPage();
    if (page_slice_o) |pg| {
        return pg.ptr;
    } else return null;
}

/// Frees page
/// Failures are in the case of a bad given address
pub fn freePage(pa: PagePtr) !void {
    const pa_u: usize = @intFromPtr(pa);
    if (pa_u % riscv.PGSIZE != 0) return error.AddressNotPageAligned;
    const end_u: usize = @intFromPtr(end);
    if (pa_u < end_u) return error.AddressTooLow;
    if (pa_u >= memlayout.PHYSTOP) return error.AddressTooHigh;
    // // Fill with junk to catch dangling refs.
    @memset(pa[0..riscv.PGSIZE], 1);
    const b: *Block = @alignCast(@ptrCast(pa));
    lock.acquire();
    defer lock.release();
    b.next = freelist;
    freelist = b;
}

pub const PagePtr = *align(riscv.PGSIZE) [riscv.PGSIZE]u8;

pub fn allocPage() ?PagePtr {
    lock.acquire();
    defer lock.release();
    const r_o = freelist;
    if (r_o) |r| {
        freelist = r.next;
    }
    if (r_o) |r| {
        const ptr: [*]u8 = @ptrCast(r);
        @memset(ptr[0..riscv.PGSIZE], 5);
    } else {
        // log.warn("out of memory", .{});
        return null;
    }
    const ptr: [*]align(riscv.PGSIZE) u8 = @alignCast(@ptrCast(r_o.?));
    return ptr[0..riscv.PGSIZE];
}

pub const page_allocator = std.mem.Allocator{
    .ptr = undefined,
    .vtable = &std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .free = free,
    },
};

fn alloc(_: *anyopaque, n: usize, log2_align: u8, ra: usize) ?[*]u8 {
    _ = ra;
    _ = log2_align;
    assert(n > 0);
    if (n > std.math.maxInt(usize) - (riscv.PGSIZE - 1)) return null;
    if (n > riscv.PGSIZE) @panic("Unimplemented: n > PGSIZE");
    const aligned_len = std.mem.alignForward(usize, n, riscv.PGSIZE);
    const page_count = aligned_len / riscv.PGSIZE;
    var start_slice = allocPage() orelse return null;
    for (1..page_count) |i| {
        var new_slice = allocPage() orelse {
            for (0..i) |j| {
                freePage(@alignCast(start_slice.ptr[j * riscv.PGSIZE ..][0..riscv.PGSIZE])) catch @panic("Alloc failed");
            }
            return null;
        };
        const start_ptr_u: usize = @ptrFromInt(start_slice.ptr);
        const new_ptr_u: usize = @ptrFromInt(new_slice.ptr);
        if (start_ptr_u + i * riscv.PGSIZE != new_ptr_u) {
            for (0..i) |j| {
                freePage(@alignCast(start_slice.ptr[j * riscv.PGSIZE ..][0..riscv.PGSIZE])) catch @panic("Freeing after alloc failure failed");
            }
            freePage(new_slice) catch @panic("Freeing after alloc failure failed");
            return null;
        }
    }
    assert(std.mem.isAligned(@intFromPtr(start_slice.ptr), riscv.PGSIZE));
    return start_slice.ptr;
}

fn resize(
    _: *anyopaque,
    buf_unaligned: []u8,
    log2_buf_align: u8,
    new_size: usize,
    return_address: usize,
) bool {
    _ = return_address;
    _ = log2_buf_align;
    const new_size_aligned = std.mem.alignForward(usize, new_size, riscv.PGSIZE);
    const buf_aligned_len = std.mem.alignForward(usize, buf_unaligned.len, riscv.PGSIZE);
    if (new_size_aligned == buf_aligned_len) return true;
    if (new_size_aligned < buf_aligned_len) {
        for (0..(buf_aligned_len - new_size_aligned) / riscv.PGSIZE) |i| {
            freePage(@alignCast(buf_unaligned.ptr[i * riscv.PGSIZE ..][0..riscv.PGSIZE])) catch @panic("Could not free page");
        }
        return true;
    }
    return false;
}

fn free(_: *anyopaque, slice: []u8, log2_buf_align: u8, return_address: usize) void {
    _ = return_address;
    _ = log2_buf_align;
    const buf_aligned_len = std.mem.alignForward(usize, slice.len, riscv.PGSIZE);
    const page_count = buf_aligned_len / riscv.PGSIZE;
    for (0..page_count) |i| {
        freePage(@alignCast(slice.ptr[i * riscv.PGSIZE ..][0..riscv.PGSIZE])) catch @panic("Could not free page");
    }
}
