const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const common = @import("common");
const Color = common.color.Color;
const sys = @import("user.zig");

const c = @cImport({
    @cInclude("kernel/types.h");
    @cInclude("kernel/param.h");
    @cInclude("kernel/spinlock.h");
    @cInclude("kernel/sleeplock.h");
    @cInclude("kernel/fs.h");
    @cInclude("kernel/file.h");
    @cInclude("kernel/memlayout.h");
    @cInclude("kernel/riscv.h");
    @cInclude("kernel/defs.h");
    @cInclude("kernel/proc.h");
});

/// The errors that can occur when logging
const LoggingError = error{};

/// The Writer for the format function
const Writer = std.io.Writer(void, LoggingError, logCallback);

fn writeByte(b: u8) !void {
    // Suppress unused var warning
    const b_p: [*]const u8 = @ptrCast(&b);
    _ = try sys.write(1, b_p[0..1]);
}

fn logCallback(context: void, str: []const u8) LoggingError!usize {
    _ = context;
    // Suppress unused var warning
    return sys.write(1, str) catch @panic("log write error");
}

pub fn UlogFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = scope;
    @setRuntimeSafety(false);

    // const scope_prefix = "(" ++ comptime Color.cyan.ttyStr() ++ @tagName(scope) ++ Color.reset.ttyStr() ++ ") ";

    const prefix =
        // scope_prefix ++
        "[" ++ comptime logLevelColor(level).ttyStr() ++ level.asText() ++ Color.reset.ttyStr() ++ "]: ";
    print(prefix ++ format ++ "\n", args);
}

pub fn logLevelColor(lvl: std.log.Level) Color {
    return switch (lvl) {
        .err => .red,
        .warn => .yellow,
        .debug => .magenta,
        .info => .green,
    };
}

fn cPanic(s: [*:0]u8) callconv(.C) noreturn {
    @setCold(true);
    _ = sys.write(1, std.mem.span(s)) catch @panic("log write error");

    sys.exit(1);
}
comptime {
    @export(cPanic, .{ .name = "panic", .linkage = .Strong });
}

pub fn panic(
    msg: []const u8,
    error_return_trace: ?*std.builtin.StackTrace,
    _: ?usize,
) noreturn {
    _ = error_return_trace;
    @setCold(true);
    const panic_log = std.log.scoped(.panic);
    panic_log.err("{s}", .{msg});
    sys.exit(1);
}

pub fn print(comptime format: []const u8, args: anytype) void {
    fmt.format(Writer{ .context = {} }, format, args) catch |err| {
        @panic("format: " ++ @errorName(err));
    };
}

pub export fn printf(format: [*:0]const u8, ...) void {
    @setRuntimeSafety(false);
    if (std.mem.span(format).len == 0) @panic("null fmt");

    var ap = @cVaStart();
    var skip_idx: usize = undefined;
    for (std.mem.span(format), 0..) |byte, i| {
        if (i == skip_idx) {
            continue;
        }
        if (byte != '%') {
            writeByte(byte) catch @panic("write byte failed");
            continue;
        }
        var ch = format[i + 1] & 0xff;
        skip_idx = i + 1;
        if (ch == 0) break;
        switch (ch) {
            'd' => print("{d}", .{@cVaArg(&ap, c_int)}),
            'x' => print("{x}", .{@cVaArg(&ap, c_int)}),
            'p' => print("{p}", .{@cVaArg(&ap, *usize)}),
            's' => {
                var s = std.mem.span(@cVaArg(&ap, [*:0]const u8));
                print("{s}", .{s});
            },
            '%' => writeByte('%') catch @panic("write byte failed"),
            else => {
                // Print unknown % sequence to draw attention.
                writeByte('%') catch @panic("write byte failed");
                writeByte(ch) catch @panic("write byte failed");
            },
        }
    }
    @cVaEnd(&ap);
}
