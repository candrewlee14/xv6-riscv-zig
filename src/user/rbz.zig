const c = @cImport({
    @cInclude("kernel/types.h");
    @cInclude("kernel/stat.h");
    @cInclude("user/user.h");
});
const std = @import("std");
const sys = @import("./ulib/user.zig");
const usr = @import("./ulib/user_high.zig");
const Color = @import("common").color.Color;
const rb = @import("./ulib/uringbuf.zig");

const CHUNK_LEN = 510; // for testing that non-PIPESIZE writes work
const WRITE_AMT = 10 * 1024 * 1024;

fn zmain() !void {
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
    c.printf("Running benchmark...\n");
    if (try sys.fork()) |pid| {
        _ = pid;
        // parent (pid is not null, so pid is for the child)
        const rb_desc = try rb.init(rb_name);
        const rb_p = rb.getRingbuf(rb_desc);
        defer rb_p.deactivate();
        c.printf("RB activated!");
        //
        // var n_read: usize = 0;
        // var read_buf: [CHUNK_LEN]u8 = undefined;
        // const t_before = sys.uptime();
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
        // const t_after = sys.uptime();
        // c.printf("Elapsed ticks: %d\n", t_after - t_before);
        // var exit_status: i32 = undefined;
        // if (pid != sys.wait(&exit_status)) {
        //     c.printf("Unexpected child PID for wait\n");
        //     return error.WrongChild;
        // }
        // if (exit_status != 0) {
        //     c.printf("Child returned bad exit status: %d\n", exit_status);
        //     return error.ChildError;
        // }
    } else {
        // // child
        // var n_written: usize = 0;
        // const rb_desc = try rb.init(rb_name);
        // const rb_p = rb.getRingbuf(rb_desc);
        // defer rb_p.deactivate();
        //
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

export fn main() c_int {
    zmain() catch |err| {
        // This switch case handles the possible error types from main
        // by printing the error's name as a string.
        // Example: @errorName(error.PipeError) => "PipeError"
        // This is done using some compile-time reflection magic.
        switch (err) {
            inline else => |err_val| c.printf(
                comptime Color.red.ttyStr() ++
                    "ERROR: %s\n" ++
                    Color.reset.ttyStr(),
                @errorName(err_val),
            ),
        }
        c.exit(1);
    };
    c.exit(0);
}
