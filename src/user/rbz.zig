const std = @import("std");
const sys = @import("./ulib/user.zig");
const usr = @import("./ulib/user_high.zig");
const Color = @import("common").color.Color;
const rb = @import("./ulib/uringbuf.zig");
const log_root = @import("./ulib/ulog.zig");

const mixin = @import("./ulib/mixin.zig");
usingnamespace mixin.ProgMixin;
// root overrides for std lib
pub const std_options = mixin.std_options;
pub const os = mixin.os;

const logger = std.log.scoped(.rbz);

const CHUNK_LEN = 510; // for testing that non-PIPESIZE writes work
const WRITE_AMT = 10 * 1024 * 1024;

pub fn main() !void {
    // Build a chunk of CHUNK_LEN chars.
    // The contents look like this:
    //   abcdefghijklmo...
    const chunk: [CHUNK_LEN]u8 = blk: {
        var chunk = [_]u8{'a'} ** CHUNK_LEN;
        for (&chunk, 0..) |*ch, i| {
            ch.* += @intCast(i % 26);
        }
        break :blk chunk;
    };
    _ = chunk;
    const rb_name: [*:0]const u8 = "Ringbuf1";
    logger.info("Running benchmark...", .{});
    if (try sys.fork()) |pid| {
        // parent (pid is not null, so pid is for the child)
        const rb_desc = try rb.init(rb_name);
        const rb_p = rb.getRingbuf(rb_desc);
        defer rb_p.deactivate();
        //
        // var n_read: usize = 0;
        // var read_buf: [CHUNK_LEN]u8 = undefined;
        const t_before = sys.uptime();
        // while (n_read < WRITE_AMT) {
        //     const buf = rb_p.startRead();
        //     const pos = n_read % chunk.len;
        //     const read_amt = @min(chunk.len - pos, buf.len);
        //     @memcpy(read_buf[pos..], buf[0..read_amt]);
        //     rb_p.finishRead(read_amt);
        //     if (!std.mem.eql(u8, read_buf[pos..][0..read_amt], chunk[pos..][0..read_amt])) {
        //         c.printf("The byte stream read did not match written stream!\n");
        //         return error.MismatchByteStreams;
        //     }
        //     n_read += read_amt;
        // }
        const t_after = sys.uptime();
        logger.info("Elapsed ticks: {d}", .{t_after - t_before});
        var exit_status: i32 = undefined;
        if (pid != sys.wait(&exit_status)) {
            logger.err("Unexpected child PID for wait", .{});
            return error.WrongChild;
        }
        if (exit_status != 0) {
            logger.err("Child returned bad exit status: {d}", .{exit_status});
            return error.ChildError;
        }
    } else {
        // // child
        var n_written: usize = 0;
        const rb_desc = try rb.init(rb_name);
        const rb_p = rb.getRingbuf(rb_desc);
        defer rb_p.deactivate();

        const buf = rb_p.startWrite();
        // log.print("Running benchmark...", .{});

        // touch each page just to see if we fault
        rb_p.finishWrite(buf.len);
        n_written += buf.len;

        // while (n_written < WRITE_AMT) {
        //     const buf = rb_p.startWrite();
        //     const pos = n_written % chunk.len;
        //     const write_amt = @min(chunk.len - pos, buf.len);
        //     @memcpy(buf, chunk[0..write_amt]);
        //     rb_p.finishWrite(write_amt);
        //     n_written += write_amt;
        // }
    }
}
