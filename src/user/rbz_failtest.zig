const std = @import("std");
const sys = @import("./ulib/user.zig");
const usr = @import("./ulib/user_high.zig");
const com = @import("common");
const com_rb = @import("common").ringbuf;
const rb = @import("./ulib/uringbuf.zig");
const log_root = @import("./ulib/ulog.zig");
const RndGen = std.rand.DefaultPrng;

const mixin = @import("./ulib/mixin.zig");
usingnamespace mixin.ProgMixin;
// root overrides for std lib
pub const std_options = mixin.std_options;
pub const os = mixin.os;

const logger = std.log.scoped(.rbz);

const RbErr = com_rb.RingbufError;

pub fn main() !void {
    {
        // NAME TOO SHORT
        var addr: ?*anyopaque = null;
        const exp_err = RbErr.BadNameLength;
        const err_str = "0 name length should've failed";
        if (sys.ringbuf("", .open, &addr)) |_| {
            logger.err(err_str, .{});
        } else |err| {
            if (err == exp_err) {
                logger.info(@errorName(exp_err) ++ ", 0 length test: OK", .{});
            } else {
                logger.err(err_str ++ ", got {any}", .{err});
            }
        }
    }
    {
        // NAME TOO LONG
        var addr: ?*anyopaque = null;
        const exp_err = RbErr.BadNameLength;
        const err_str = "name length too long should've failed";
        const name = "01234123461280347613223423423432423";
        if (sys.ringbuf(name, .open, &addr)) |_| {
            logger.err(err_str, .{});
            try sys.ringbuf(name, .close, &addr);
        } else |err| {
            if (err == exp_err) {
                logger.info(@errorName(exp_err) ++ ", too long test: OK", .{});
            } else {
                logger.err(err_str ++ ", got {any}", .{err});
            }
        }
    }
    {
        // UNOPENED RB CAN'T BE CLOSED
        var addr: ?*anyopaque = null;
        const exp_err = RbErr.NameNotFound;
        const err_str = "unopened close should've failed";
        const name = "unopened";
        if (sys.ringbuf(name, .close, &addr)) |_| {
            logger.err(err_str, .{});
        } else |err| {
            if (err == exp_err) {
                logger.info(@errorName(exp_err) ++ " test: OK", .{});
            } else {
                logger.err(err_str ++ ", got {any}", .{err});
            }
        }
    }
    {
        // NO ADDR GIVEN TO CLOSE
        var null_addr: ?*anyopaque = null;
        var addr: ?*anyopaque = null;
        const exp_err = RbErr.NoAddrGiven;
        const err_str = "no addr given to close should've failed";
        const name = "no_addr";
        try sys.ringbuf(name, .open, &addr);
        if (sys.ringbuf(name, .close, &null_addr)) |_| {
            logger.err(err_str, .{});
        } else |err| {
            if (err == exp_err) {
                logger.info(@errorName(exp_err) ++ " test: OK", .{});
            } else {
                logger.err(err_str ++ ", got {any}", .{err});
            }
        }
    }
    {
        // CLOSE ADDR NOT MATCHING OPEN ADDR
        var bad_addr: ?*anyopaque = @ptrFromInt(4096 * 100);
        var addr: ?*anyopaque = null;
        const exp_err = RbErr.BadAddr;
        const err_str = "mismatch ringbuf close addr should've failed";
        const name = "bad_addr";
        try sys.ringbuf(name, .open, &addr);
        if (sys.ringbuf(name, .close, &bad_addr)) |_| {
            logger.err(err_str, .{});
        } else |err| {
            if (err == exp_err) {
                logger.info(@errorName(exp_err) ++ " test: OK", .{});
            } else {
                logger.err(err_str ++ ", got {any}", .{err});
            }
        }
    }
}
