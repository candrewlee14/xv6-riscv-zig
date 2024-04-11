const root = @import("root");
const std = @import("std");
const log = @import("./ulog.zig");
const Color = @import("common").color.Color;
const sys = @import("./user.zig");

pub const ProgMixin = struct {
    pub fn c_main() callconv(.C) c_int {
        root.main() catch |err| {
            // This switch case handles the possible error types from main
            // by printing the error's name as a string.
            // Example: @errorName(error.PipeError) => "PipeError"
            // This is done using some compile-time reflection magic.
            switch (err) {
                inline else => |err_val| log.printf(
                    comptime Color.red.ttyStr() ++
                        "ERROR: %s\n" ++
                        Color.reset.ttyStr(),
                    @errorName(err_val),
                ),
            }
            sys.exit(1);
        };
        sys.exit(0);
    }
    comptime {
        @export(c_main, .{ .name = "main", .linkage = .strong });
        @export(c_main, .{ .name = "_start", .linkage = .strong });
    }
};

pub const std_options = std.Options{
    // Set the log level to info
    .log_level = .debug,
    // Define logFn to override the std implementation
    .logFn = log.ulogFn,
};

// This is a dummy implementation of the os package for the purposes of
// printing and logging.
pub const os = struct {
    pub const system = struct {
        pub const fd_t = c_int;
        pub const STDERR_FILENO = 1;
        pub const E = std.os.linux.E;

        pub fn getErrno(T: usize) E {
            _ = T;
            return .SUCCESS;
        }

        pub fn write(f: fd_t, ptr: [*]const u8, len: usize) usize {
            return sys.write(f, ptr[0..len]) catch @panic("write failed");
        }
    };
};
