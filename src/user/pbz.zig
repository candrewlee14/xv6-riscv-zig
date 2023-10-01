const std = @import("std");
const sys = @import("./ulib/user.zig");
const usr = @import("./ulib/user_high.zig");
const Color = @import("common").color.Color;
const log_root = @import("./ulib/ulog.zig");

const mixin = @import("./ulib/mixin.zig");
usingnamespace mixin.ProgMixin;
// root overrides for std lib
pub const std_options = mixin.std_options;
pub const os = mixin.os;

const logger = std.log.scoped(.pbz);

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
    logger.info("Running benchmark...", .{});

    const pipe = try usr.Pipe.init();
    if (try sys.fork()) |pid| {
        // parent (pid is not null, so pid is for the child)
        pipe.closeWrite();
        defer pipe.closeRead();
        var n_read: usize = 0;
        var read_buf: [CHUNK_LEN]u8 = undefined;
        const t_before = sys.uptime();
        while (n_read < WRITE_AMT) {
            n_read += try pipe.read(&read_buf);
            if (!std.mem.eql(u8, &read_buf, &chunk)) {
                logger.err("The byte stream read did not match written stream!", .{});
                return error.MismatchByteStreams;
            }
        }
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
        // child
        pipe.closeRead();
        defer pipe.closeWrite();
        var n_written: usize = 0;
        while (n_written < WRITE_AMT) {
            n_written += try pipe.write(&chunk);
        }
    }
}
