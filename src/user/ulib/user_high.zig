const sys = @import("user.zig");
const com = @import("common");
const riscv = com.riscv;
const Book = com.ringbuf.Book;

pub const Pipe = packed struct {
    read_fd: sys.FileDescriptor,
    write_fd: sys.FileDescriptor,

    pub fn init() !Pipe {
        var p: Pipe = undefined;
        try sys.pipe(@ptrCast(&p));
        return p;
    }
    pub fn closeBoth(self: *const Pipe) void {
        sys.close(self.read_fd) catch unreachable;
        sys.close(self.write_fd) catch unreachable;
    }
    pub fn closeRead(self: *const Pipe) void {
        sys.close(self.read_fd) catch unreachable;
    }
    pub fn closeWrite(self: *const Pipe) void {
        sys.close(self.write_fd) catch unreachable;
    }
    pub fn read(self: *const Pipe, dst_buf: []u8) !usize {
        return sys.read(self.read_fd, dst_buf);
    }
    pub fn write(self: *const Pipe, src_buf: []const u8) !usize {
        return sys.write(self.write_fd, src_buf);
    }
};
