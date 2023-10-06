const std = @import("std");
const com = @import("common");
const riscv = com.riscv;
const RB = com.ringbuf;
const Book = com.ringbuf.Book;
const sys = @import("./user.zig");

var uringbufs = [_]UserRingBuf{.{
    .buf = undefined,
    .book = undefined,
    .name = undefined,
    .is_active = 0,
}} ** RB.MAX_RINGBUFS;

pub const UserRingBuf = extern struct {
    buf: RB.MagicBuf,
    book: *align(riscv.PGSIZE) Book,
    name: [*:0]const u8,
    is_active: c_int,

    pub fn open(self: *UserRingBuf, name: [*:0]const u8) !void {
        if (self.is_active == 1) return error.AlreadyActive;
        var buf_p: ?*anyopaque = null;
        try sys.ringbuf(name, .open, &buf_p);
        const buf_u: usize = @intFromPtr(buf_p);
        const book_u = buf_u - riscv.PGSIZE;
        self.* = .{
            .buf = @ptrFromInt(buf_u),
            .book = @ptrFromInt(book_u),
            .name = name,
            .is_active = 1,
        };
    }
    pub fn close(self: *UserRingBuf) void {
        if (self.is_active == 0) @panic("uringbuf: already inactive");
        sys.ringbuf(self.name, .close, @ptrCast(&self.buf)) catch @panic("uringbuf: failed to close");
        self.is_active = 0;
    }
    pub fn startRead(self: *UserRingBuf) []const u8 {
        const read_done = self.book.read_done.load(.SeqCst);
        const write_done = self.book.write_done.load(.SeqCst);
        return self.buf[read_done % RB.BUF_CAPACITY ..][0 .. write_done - read_done];
    }
    pub fn finishRead(self: *UserRingBuf, byte_len: u64) void {
        std.debug.assert(self.book.write_done.load(.SeqCst) - self.book.read_done.load(.SeqCst) >= byte_len);
        _ = self.book.read_done.fetchAdd(byte_len, .SeqCst);
    }
    pub fn startWrite(self: *UserRingBuf) []u8 {
        const read_done = self.book.read_done.load(.SeqCst);
        const write_done = self.book.write_done.load(.SeqCst);
        return self.buf[write_done % RB.BUF_CAPACITY ..][0 .. RB.BUF_CAPACITY - (write_done - read_done)];
    }
    pub fn finishWrite(self: *UserRingBuf, byte_len: u64) void {
        std.debug.assert(self.book.write_done.load(.SeqCst) + byte_len - self.book.read_done.load(.SeqCst) <= RB.BUF_CAPACITY);
        _ = self.book.write_done.fetchAdd(byte_len, .SeqCst);
    }
};

pub const UringbufDescriptor = usize;

pub fn init(name: [*:0]const u8) !UringbufDescriptor {
    const name_str = std.mem.span(name);
    const urb_i: UringbufDescriptor = blk: {
        for (&uringbufs, 0..) |urb, i| {
            if (std.mem.eql(u8, name_str, std.mem.span(urb.name))) return i;
            if (urb.is_active == 0) break :blk i;
        }
        return error.NoFreeRingbuf;
    };
    try uringbufs[urb_i].open(name);
    return urb_i;
}
pub fn deinit(rb_desc: UringbufDescriptor) void {
    uringbufs[rb_desc].close();
}
pub fn getRingbuf(rb_desc: UringbufDescriptor) *UserRingBuf {
    return &uringbufs[rb_desc];
}

pub export fn ringbuf_init(name: [*:0]const u8) c_int {
    return @intCast(init(name) catch return -1);
}
pub export fn ringbuf_deinit(rb_desc: c_int) void {
    deinit(@intCast(rb_desc));
}

export fn ringbuf_start_read(ring_desc: c_int, addr: *?*c_char, bytes: *c_int) void {
    const buf = uringbufs[@intCast(ring_desc)].startRead();
    addr.* = @constCast(@ptrCast(buf.ptr));
    bytes.* = @intCast(buf.len);
}

export fn ringbuf_finish_read(ring_desc: c_int, bytes: c_int) void {
    uringbufs[@intCast(ring_desc)].finishRead(@intCast(bytes));
}

export fn ringbuf_start_write(ring_desc: c_int, addr: *?[*]u8, bytes: *c_int) void {
    const buf = uringbufs[@intCast(ring_desc)].startWrite();
    addr.* = @ptrCast(buf.ptr);
    bytes.* = @intCast(buf.len);
}

export fn ringbuf_finish_write(ring_desc: c_int, bytes: c_int) void {
    uringbufs[@intCast(ring_desc)].finishWrite(@intCast(bytes));
}
