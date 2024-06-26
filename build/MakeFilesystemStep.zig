// Much of this code comes from https://github.com/binarycraft007/xv6-riscv-zig

const std = @import("std");
const builtin = @import("builtin");
const os = std.os;
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;
const MakeFilesystemStep = @This();

const Build = std.Build;
const InstallDir = Build.InstallDir;
const CompileStep = Build.Step.Compile;
const Step = Build.Step;

const fs = @import("fs.zig");
const stat = @import("../src/common/stat.zig");
const param = @import("../src/common/param.zig");

const NINODES = 200;

// Disk layout:
// [ boot block | sb block | log | inode blocks | free bit map | data blocks ]

const nbitmap: i32 = param.FSSIZE / (fs.BSIZE * 8) + 1;
const ninodeblocks: i32 = NINODES / fs.IPB + 1;
const nlog: i32 = param.LOGSIZE;

const zeroes = [_]u8{0} ** fs.BSIZE;
var sb: fs.SuperBlock = undefined;
var freeinode: u32 = 1;
var freeblock: u32 = undefined;
var file: std.fs.File = undefined;

step: Step,
artifacts: std.ArrayList(*CompileStep),
dest_dir: InstallDir,
dest_filename: []const u8,
output_file: std.Build.GeneratedFile,

pub fn create(
    owner: *Build,
    artifacts: std.ArrayList(*CompileStep),
    dest_filename: []const u8,
) *MakeFilesystemStep {
    const self = owner.allocator.create(MakeFilesystemStep) catch @panic("OOM");
    self.* = MakeFilesystemStep{
        .step = Step.init(.{
            .id = .custom,
            .owner = owner,
            .name = owner.fmt("make filesystem image {s}", .{dest_filename}),
            .makeFn = make,
        }),
        .artifacts = artifacts,
        .dest_dir = .bin,
        .dest_filename = dest_filename,
        .output_file = std.Build.GeneratedFile{ .step = &self.step },
    };

    for (artifacts.items) |artifact| {
        self.step.dependOn(&artifact.step);
    }

    owner.pushInstalledFile(self.dest_dir, dest_filename);
    return self;
}

pub fn getOutputSource(self: *const MakeFilesystemStep) std.Build.LazyPath {
    return std.Build.LazyPath{ .generated = &self.output_file };
}

fn make(step: *Step, prog_node: *std.Progress.Node) !void {
    _ = prog_node;
    const self: *MakeFilesystemStep = @fieldParentPtr("step", step);
    const b = self.step.owner;

    var full_src_paths = std.ArrayList([]const u8).init(b.allocator);
    try full_src_paths.append("README.md");
    for (self.artifacts.items) |artifact| {
        try full_src_paths.append(artifact.getEmittedBin().getPath(b));
    }

    const full_dest_path = b.getInstallPath(self.dest_dir, self.dest_filename);
    self.output_file.path = full_dest_path;

    std.fs.cwd().makePath(b.getInstallPath(self.dest_dir, "")) catch unreachable;

    var dir = try std.fs.cwd().openDir(b.getInstallPath(self.dest_dir, ""), .{});
    defer dir.close();

    var de: fs.Dirent = undefined;
    var buf: [fs.BSIZE]u8 = undefined;
    var din: fs.Dinode = undefined;

    assert(fs.BSIZE % @sizeOf(fs.Dinode) == 0);
    assert(fs.BSIZE % @sizeOf(fs.Dirent) == 0);

    var flags = std.fs.File.CreateFlags{
        .read = true,
        .truncate = true,
    };
    if (builtin.os.tag != .windows) {
        flags.mode = std.c.S.IRUSR | std.c.S.IWUSR | std.c.S.IRGRP | std.c.S.IWGRP |
            std.c.S.IROTH | std.c.S.IWOTH;
    }
    file = try dir.createFile(self.dest_filename, flags);
    defer file.close();

    const nmeta = 2 + nlog + ninodeblocks + nbitmap;
    const nblocks = param.FSSIZE - nmeta;

    sb = fs.SuperBlock{
        .magic = fs.FSMAGIC,
        .size = param.FSSIZE,
        .nblocks = nblocks,
        .ninodes = NINODES,
        .nlog = nlog,
        .logstart = 2,
        .inodestart = 2 + nlog,
        .bmapstart = 2 + nlog + ninodeblocks,
    };

    freeblock = nmeta; // the first free block that we can allocate
    var i: usize = 0;
    while (i < param.FSSIZE) : (i += 1) {
        try wsect(i, &zeroes);
    }

    @memset(&buf, 0);
    const mem_bytes = mem.asBytes(&sb);
    @memcpy(buf[0..mem_bytes.len], mem_bytes);
    try wsect(1, &buf);

    const rootino = @as(u16, @intCast(try ialloc(.dir)));
    std.debug.assert(rootino == fs.ROOTINO);

    @memset(mem.asBytes(&de), 0);
    de.inum = mem.readVarInt(u16, mem.asBytes(&rootino), .little);
    @memcpy(de.name[0..1], ".");
    try iappend(@as(u32, rootino), mem.asBytes(&de));

    @memset(mem.asBytes(&de), 0);
    de.inum = mem.readVarInt(u16, mem.asBytes(&rootino), .little);
    @memcpy(de.name[0..2], "..");
    try iappend(@as(u32, rootino), mem.asBytes(&de));

    for (full_src_paths.items) |full_src_path| {
        const path = full_src_path;
        var shortname = std.fs.path.basename(path);

        const bin = try std.fs.cwd().openFile(path, .{});
        defer bin.close();

        if (shortname[0] == '_') {
            shortname = shortname[1..];
        }

        var inum = @as(u16, @intCast(try ialloc(.file)));
        @memset(mem.asBytes(&de), 0);
        de.inum = mem.readVarInt(u16, mem.asBytes(&inum), .little);
        @memcpy(de.name[0..shortname.len], shortname);
        try iappend(@as(u32, rootino), mem.asBytes(&de));

        while (true) {
            const amt = try bin.reader().read(&buf);
            if (amt == 0) break;
            try iappend(@as(u32, inum), buf[0..amt]);
        }
    }

    // fix size of root inode dir
    try rinode(@as(u32, rootino), &din);
    var off = mem.readVarInt(u32, mem.asBytes(&din.size), .little);
    off = ((off / fs.BSIZE) + 1) * fs.BSIZE;
    din.size = mem.readVarInt(u32, mem.asBytes(&off), .little);
    try winode(@as(u32, rootino), &din);

    try balloc(@as(usize, freeblock));
}

fn wsect(sec: usize, buf: []const u8) !void {
    std.debug.assert(buf.len == fs.BSIZE);
    try file.seekTo(sec * fs.BSIZE);
    const num_write = try file.writer().write(buf);
    std.debug.assert(num_write == buf.len);
}

fn rsect(sec: usize, buf: []u8) !void {
    std.debug.assert(buf.len == fs.BSIZE);
    try file.seekTo(sec * fs.BSIZE);
    const num_read = try file.reader().read(buf);
    std.debug.assert(num_read == buf.len);
}

fn winode(inum: u32, ip: *fs.Dinode) !void {
    var buf: [fs.BSIZE]u8 = undefined;
    const bn = sb.IBLOCK(inum);
    try rsect(bn, &buf);
    const dip = buf[(inum % fs.IPB) * @sizeOf(fs.Dinode) ..];
    const mem_bytes = mem.asBytes(ip);
    @memcpy(dip[0..mem_bytes.len], mem_bytes);
    try wsect(bn, &buf);
}

fn rinode(inum: u32, ip: *fs.Dinode) !void {
    var buf: [fs.BSIZE]u8 = undefined;
    const bn = sb.IBLOCK(inum);
    try rsect(bn, &buf);
    var dip = buf[(inum % fs.IPB) * @sizeOf(fs.Dinode) ..];
    @memcpy(mem.asBytes(ip), dip[0..@sizeOf(fs.Dinode)]);
}

fn ialloc(@"type": stat.FileType) !u32 {
    const inum = freeinode;
    defer freeinode += 1;

    var din: fs.Dinode = undefined;
    @memset(mem.asBytes(&din), 0);
    var din_bytes = mem.toBytes(@intFromEnum(@"type"));
    din.type = mem.readVarInt(i16, &din_bytes, .little);
    din.nlink = mem.readVarInt(i16, &[_]u8{1}, .little);
    din.size = mem.readVarInt(u32, &[_]u8{0}, .little);

    try winode(inum, &din);
    return inum;
}

fn balloc(used: usize) !void {
    var buf: [fs.BSIZE]u8 = undefined;
    @memset(&buf, 0);

    std.debug.assert(used < fs.BSIZE * 8);

    for (0..used) |i| {
        buf[i / 8] |= @as(u8, 0x1) << @as(u3, @intCast((i % 8)));
    }

    try wsect(sb.bmapstart, &buf);
}

fn iappend(inum: u32, data: []const u8) !void {
    var din: fs.Dinode = undefined;
    var buf: [fs.BSIZE]u8 = undefined;
    var n: usize = data.len;
    var n1: usize = undefined;
    var idx: usize = 0;
    var indirect: [fs.NINDIRECT]u32 = undefined;

    try rinode(inum, &din);
    var off = mem.readVarInt(u32, mem.asBytes(&din.size), .little);

    while (n > 0) : ({
        n -= n1;
        off += @as(u32, @intCast(n1));
        idx += n1;
    }) {
        const fbn = off / fs.BSIZE;
        std.debug.assert(fbn < fs.MAXFILE);
        const x = if (fbn < fs.NDIRECT) blk: {
            if (mem.readVarInt(u32, mem.asBytes(&din.addrs[fbn]), .little) == 0) {
                const fblk = mem.readVarInt(u32, mem.asBytes(&freeblock), .little);
                defer freeblock += 1;
                din.addrs[fbn] = fblk;
            }
            break :blk mem.readVarInt(usize, mem.asBytes(&din.addrs[fbn]), .little);
        } else blk: {
            if (mem.readVarInt(u32, mem.asBytes(&din.addrs[fs.NDIRECT]), .little) == 0) {
                const fblk = mem.readVarInt(u32, mem.asBytes(&freeblock), .little);
                defer freeblock += 1;
                din.addrs[fs.NDIRECT] = fblk;
            }
            const num = mem.readVarInt(usize, mem.asBytes(&din.addrs[fs.NDIRECT]), .little);
            try rsect(num, mem.sliceAsBytes(&indirect));
            if (indirect[fbn - fs.NDIRECT] == 0) {
                const fblk = mem.readVarInt(u32, mem.asBytes(&freeblock), .little);
                defer freeblock += 1;
                indirect[fbn - fs.NDIRECT] = fblk;
                try wsect(num, mem.sliceAsBytes(&indirect));
            }
            break :blk mem.readVarInt(usize, mem.asBytes(&indirect[fbn - fs.NDIRECT]), .little);
        };
        n1 = @min(n, (fbn + 1) * fs.BSIZE - off);
        try rsect(x, &buf);
        @memcpy(buf[off - (fbn * fs.BSIZE) ..][0..n1], data[idx..][0..n1]);
        try wsect(x, &buf);
    }
    din.size = mem.readVarInt(u32, mem.asBytes(&off), .little);
    try winode(inum, &din);
}
