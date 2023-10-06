const std = @import("std");
const Atomic = std.atomic.Atomic;
const riscv = @import("./riscv.zig");

pub const RINGBUF_SIZE = 16;
pub const MAX_NAME_LEN = 16;
pub const MAX_RINGBUFS = 10;

pub const BUF_CAPACITY = RINGBUF_SIZE * riscv.PGSIZE;

pub const MagicBuf = *align(riscv.PGSIZE) [BUF_CAPACITY * 2]u8;

pub const Book = extern struct {
    read_done: Atomic(u64) = Atomic(u64).init(0),
    write_done: Atomic(u64) = Atomic(u64).init(0),
};

pub const Op = enum(u8) {
    open = 1,
    close = 0,
};

pub const RingbufError = error{
    AlreadyActive,
    AlreadyIsOwner,
    AlreadyTwoOwners,
    NoOriginalOwner,
    BadNameLength,
    OutOfMemory,
    NoFreeRingbuf,
    MapPagesFailed,
    CopyOutFailed,
    CopyInFailed,
    NoAddrGiven,
    NameNotFound,
    NotOwner,
    BadAddr,
    AlreadyInactive,
};

pub fn intFromErr(comptime ErrT: type, err: ErrT) isize {
    const fields = comptime std.meta.fields(ErrT);
    inline for (fields, 1..) |field, iu| {
        const i: isize = @intCast(iu);
        if (err == @field(ErrT, field.name)) return -i;
    }
    unreachable;
}

pub fn errFromInt(comptime ErrT: type, val: isize) ErrT {
    const fields = comptime std.meta.fields(ErrT);
    inline for (fields, 1..) |field, iu| {
        const i: isize = @intCast(iu);
        if (val == -i) return @field(ErrT, field.name);
    }
    @panic("bad error value");
}
