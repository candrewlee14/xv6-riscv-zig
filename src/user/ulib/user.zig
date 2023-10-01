const sys = @This();

const c = @cImport({
    @cInclude("kernel/types.h");
    @cInclude("kernel/stat.h");
    @cInclude("user/user.h");
});
const com = @import("common");
const stat = com.stat;
const std = @import("std");

pub const FileDescriptor = i32;
pub const Pid = i32;

/// Returns the child's Pid.
/// In the child process, it returns null.
pub fn fork() !?Pid {
    const v = c.fork();
    if (v < 0) return error.ForkError;
    if (v == 0) return null;
    return v;
}
// int exit(int) __attribute__((noreturn));
pub fn exit(code: i32) noreturn {
    c.exit(code);
}
// int wait(int*);
pub fn wait(status: *i32) Pid {
    return c.wait(status);
}

// int pipe(int*);
pub fn pipe(fds: *[2]FileDescriptor) !void {
    if (c.pipe(fds) < 0) return error.PipeError;
}
// int write(int, const void*, int);
pub fn write(fd: FileDescriptor, src_buf: []const u8) !usize {
    const len: c_int = @intCast(src_buf.len);
    const n_written = c.write(fd, src_buf.ptr, len);
    if (n_written < 0) return error.WriteError;
    if (n_written < src_buf.len) return error.WriteError;
    return @intCast(n_written);
}
// int read(int, void*, int);
pub fn read(fd: FileDescriptor, dst_buf: []u8) !usize {
    const len: c_int = @intCast(dst_buf.len);
    const n_read = c.read(fd, dst_buf.ptr, len);
    if (n_read < 0) return error.ReadError;
    return @intCast(n_read);
}
// int close(int);
pub fn close(fd: FileDescriptor) !void {
    if (c.close(fd) < 0) return error.CloseError;
}
// int kill(int);
pub fn kill(pid: Pid) !void {
    if (c.kill(pid) < 0) return error.KillError;
}

// int exec(const char*, char**);
pub fn exec(prog: [*c]const u8, argv: [*c][*c]const u8) noreturn {
    _ = argv;
    _ = prog;
    @panic("Exec unimplemented");
}
// int open(const char*, int);
pub fn open(file: [*c]const u8, flags: i32) !FileDescriptor {
    const res = c.open(file, flags);
    return if (res < 0) error.OpenError else res;
}
// int mknod(const char*, short, short);
pub fn mknod(file: [*c]const u8, major: c_short, minor: c_short) !FileDescriptor {
    const res = c.mknod(file, major, minor);
    return if (res < 0) error.MknodError else res;
}
// int unlink(const char*);
pub fn unlink(file: [*c]const u8) !void {
    if (c.unlink(file) < 0) return error.UnlinkError;
}
// int fstat(int fd, struct stat*);
pub fn fstat(fd: FileDescriptor, stat_obj: *stat.Stat) !void {
    if (c.fstat(fd, stat_obj) < 0) return error.FstatError;
}
// int link(const char*, const char*);
pub fn link(src: [*c]const u8, dst: [*c]const u8) !void {
    if (c.link(src, dst) < 0) return error.LinkError;
}
// int mkdir(const char*);
pub fn mkdir(dir: [*c]const u8) !void {
    if (c.mkdir(dir) < 0) return error.MkdirError;
}
// int chdir(const char*);
pub fn chdir(dir: [*c]const u8) !void {
    if (c.chdir(dir) < 0) return error.ChdirError;
}
// int dup(int);
pub fn dup(fd: FileDescriptor) !FileDescriptor {
    const res = c.dup(fd);
    return if (res < 0) error.DupError else res;
}
// int getpid(void);
pub fn getpid() !Pid {
    const res = c.getpid();
    return if (res < 0) error.PidError else res;
}
// char* sbrk(int);n
pub fn sbrk(n: i32) [*c]u8 {
    return c.sbrk(n);
}
// int sleep(int);
pub fn sleep(n_ticks: i32) !void {
    return c.sleep(@intCast(n_ticks));
}
// int uptime(void);
pub fn uptime() i32 {
    return c.uptime();
}

pub const OpenAction = enum(u1) {
    open = 1,
    close = 0,
};

// int ringbuf(const char* name, int open, void** addr);
pub fn ringbuf(name: [*:0]const u8, open_action: OpenAction, addr: *?*anyopaque) !void {
    if (c.ringbuf(name, @intFromEnum(open_action), addr) < 0) return error.RingbufError;
}
