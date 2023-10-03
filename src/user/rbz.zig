const std = @import("std");
const sys = @import("./ulib/user.zig");
const usr = @import("./ulib/user_high.zig");
const Color = @import("common").color.Color;
const rb = @import("./ulib/uringbuf.zig");
const log_root = @import("./ulib/ulog.zig");
const RndGen = std.rand.DefaultPrng;

const mixin = @import("./ulib/mixin.zig");
usingnamespace mixin.ProgMixin;
// root overrides for std lib
pub const std_options = mixin.std_options;
pub const os = mixin.os;

const logger = std.log.scoped(.rbz);

const RAND_SEED = 42;
const WRITE_AMT = 10 * 1024 * 1024; // 10 MB

pub fn main() !void {
    const rb_name: [*:0]const u8 = "Ringbuf1";
    logger.info("Running benchmark...", .{});
    if (try sys.fork()) |pid| {
        // parent (pid is not null, so pid is for the child)
        var rng = RndGen.init(RAND_SEED);
        var byte_rnd = rng.random();

        const rb_desc = try rb.init(rb_name);
        defer rb.deinit(rb_desc);
        const rb_p = rb.getRingbuf(rb_desc);

        var n_read: usize = 0;
        const t_before = sys.uptime();
        while (n_read < WRITE_AMT) {
            const buf = rb_p.startRead();
            // if (buf.len > 0) logger.debug("Reading {d} bytes", .{buf.len});
            for (buf) |byte| {
                if (byte != byte_rnd.int(u8)) {
                    logger.err("The byte stream read did not match written stream!", .{});
                    return error.MismatchByteStreams;
                }
            }
            rb_p.finishRead(buf.len);
            n_read += buf.len;
        }
        const t_after = sys.uptime();
        var exit_status: i32 = undefined;
        if (pid != sys.wait(&exit_status)) {
            logger.err("Unexpected child PID for wait", .{});
            return error.WrongChild;
        }
        logger.info("Elapsed ticks: {d}", .{t_after - t_before});
        if (exit_status != 0) {
            logger.err("Child returned bad exit status: {d}", .{exit_status});
            return error.ChildError;
        }
    } else {
        // child
        var rng = RndGen.init(RAND_SEED);
        var rnd = rng.random();

        var size_rng = RndGen.init(RAND_SEED + 1);
        var size_rnd = size_rng.random();

        var n_written: usize = 0;
        const rb_desc = try rb.init(rb_name);
        const rb_p = rb.getRingbuf(rb_desc);
        defer rb_p.close();

        while (n_written < WRITE_AMT) {
            const buf = rb_p.startWrite();
            const write_amt = size_rnd.intRangeAtMostBiased(usize, 0, buf.len);
            for (buf[0..write_amt]) |*byte| {
                byte.* = rnd.int(u8);
            }
            rb_p.finishWrite(write_amt);
            n_written += write_amt;
        }
    }
}
