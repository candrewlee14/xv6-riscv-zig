const c = @cImport({
    @cInclude("kernel/types.h");
    @cInclude("kernel/stat.h");
    @cInclude("user/user.h");
});
const std = @import("std");
const sys = @import("../user/user.zig");
const usr = @import("../user/user_high.zig");
const color = @import("../user/color.zig").Color;

const CHUNK_LEN = 512;
const WRITE_AMT = 10 * 1024 * 1024;

fn zmain() !void {
    // Build a chunk of CHUNK_LEN chars.
    // The contents look like this:
    //   abcdefghijklmo...
    const chunk = blk: {
        var chunk = [_]u8{'a'} ** CHUNK_LEN;
        for (&chunk, 0..) |*ch, i| {
            ch.* += @intCast(i % 26);
        }
        break :blk chunk;
    };
    c.printf("Running benchmark...\n");

    const pipe = try usr.Pipe.init();
    if (try sys.fork()) |pid| {
        // parent (pid is not null)
        pipe.closeWrite();
        defer pipe.closeRead();
        var n_written: usize = 0;
        var read_buf: [CHUNK_LEN]u8 = undefined;
        const t_before = sys.uptime();
        while (n_written < WRITE_AMT) {
            n_written += try pipe.read(&read_buf);
            if (!std.mem.eql(u8, &read_buf, &chunk)) {
                c.printf("The byte stream read did not match written stream!\n");
                return error.MismatchByteStreams;
            }
        }
        const t_after = sys.uptime();
        c.printf("Elapsed ticks: %d\n", t_after - t_before);
        var exit_status: i32 = undefined;
        if (pid != sys.wait(&exit_status)) {
            c.printf("Unexpected child PID for wait\n");
            return error.WrongChild;
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

export fn main() c_int {
    zmain() catch |err| {
        switch (err) {
            inline else => |err_val| c.printf(
                comptime color.red.ttyStr() ++
                    "ERROR: %s\n" ++
                    color.reset.ttyStr(),
                @errorName(err_val),
            ),
        }
        c.exit(1);
    };
    c.exit(0);
}
