const std = @import("std");
const Atomic = std.atomic.Atomic;

pub const RINGBUF_SIZE = 16;
pub const MAX_NAME_LEN = 16;
pub const MAX_RINGBUFS = 10;

pub const Book = extern struct {
    read_done: Atomic(u64) = Atomic(u64).init(0),
    write_done: Atomic(u64) = Atomic(u64).init(0),
};
