// Much of this code comes from https://github.com/binarycraft007/xv6-riscv-zig

const std = @import("std");
const mem = std.mem;
const RunStep = std.Build.RunStep;
const CompileStep = std.Build.CompileStep;
const InstallFileStep = std.Build.InstallFileStep;
const MakeFilesystemStep = @import("build/MakeFilesystemStep.zig");
const SyscallGenStep = @import("build/SyscallGenStep.zig");
const QemuRunStep = @import("build/QemuRunStep.zig");

const kernel_src = [_][]const u8{
    "src/kernel/entry.S", // Very first boot instructions.
    "src/kernel/console.c", // Connect to the user keyboard and screen.
    "src/kernel/uart.c", // Serial-port console device driver.
    "src/kernel/spinlock.c", // Locks that don’t yield the CPU.
    "src/kernel/string.c", // C string and byte-array library.
    "src/kernel/vm.c", // Manage page tables and address spaces.
    "src/kernel/proc.c", // Processes and scheduling.
    "src/kernel/swtch.S", // Thread switching.
    "src/kernel/trampoline.S", // Assembly code to switch between user and kernel.
    "src/kernel/trap.c", // C code to handle and return from traps and interrupts.
    "src/kernel/syscall.c", // Dispatch system calls to handling function.
    "src/kernel/sysproc.c", // Process-related system calls.
    "src/kernel/bio.c", // Disk block cache for the file system.
    "src/kernel/fs.c", // File system.
    "src/kernel/log.c", // File system logging and crash recovery.
    "src/kernel/sleeplock.c", // Locks that yield the CPU.
    "src/kernel/file.c", // File descriptor support.
    "src/kernel/pipe.c", // Pipes.
    "src/kernel/exec.c", // exec() system call.
    "src/kernel/sysfile.c", // File-related system calls.
    "src/kernel/kernelvec.S", // Handle traps from kernel, and timer interrupts.
    "src/kernel/plic.c", // RISC-V interrupt controller.
    "src/kernel/virtio_disk.c", // Disk device driver.
    // "src/kernel/kalloc.c", // Physical page allocator.
};

const cflags = [_][]const u8{
    "-Wall",
    "-Werror",
    "-Wno-gnu-designator", // workaround for compiler error
    "-fno-omit-frame-pointer",
    "-gdwarf-4",
    "-MD",
    "-ggdb",
    "-ffreestanding",
    "-fno-common",
    "-nostdlib",
    "-mno-relax",
    "-fno-pie",
    "-fno-stack-protector",
    "-Wno-unused-but-set-variable", // workaround for compiler error
    "-g",
};

const ProgType = enum {
    zig,
    c,
};

const Prog = struct {
    type: ProgType,
    name: []const u8,
};

const user_progs = [_]Prog{
    // "src/user/forktest.c", // ToDo: build forktest
    .{ .type = .zig, .name = "rbz" },
    .{ .type = .zig, .name = "pbz" },
    .{ .type = .c, .name = "basic_buf_test" },
    .{ .type = .c, .name = "rb" },
    .{ .type = .c, .name = "pb" },
    .{ .type = .c, .name = "cat" },
    .{ .type = .c, .name = "echo" },
    .{ .type = .c, .name = "grep" },
    .{ .type = .c, .name = "init" },
    .{ .type = .c, .name = "kill" },
    .{ .type = .c, .name = "ln" },
    .{ .type = .c, .name = "ls" },
    .{ .type = .c, .name = "mkdir" },
    .{ .type = .c, .name = "rm" },
    .{ .type = .c, .name = "sh" },
    .{ .type = .c, .name = "stressfs" },
    .{ .type = .c, .name = "usertests" },
    .{ .type = .c, .name = "grind" },
    .{ .type = .c, .name = "wc" },
    .{ .type = .c, .name = "zombie" },
};

const ulib_c_src = [_][]const u8{
    "src/user/ulib/ulib.c",
    "src/user/ulib/printf.c",
    "src/user/ulib/umalloc.c",
};

const ulib_z_src = [_][]const u8{
    "src/user/ulib/ulib.c",
    // "src/user/ulib/printf.c",
    "src/user/ulib/umalloc.c",
};

const syscalls = [_][]const u8{
    "fork", // Create a process, return childΓÇÖs PID.
    "exit", // Terminate the current process; status reported to wait(). No return.
    "wait", // Wait for a child to exit; exit status in *status; returns child PID.
    "pipe", // Create a pipe, put read/write file descriptors in p[0] and p[1].
    "read", // Read n bytes into buf; returns number read; or 0 if end of file.
    "write", // Write n bytes from buf to file descriptor fd; returns n.
    "close", // Release open file fd.
    "kill", // Terminate process PID. Returns 0, or -1 for error.
    "exec", // Load a file and execute it with arguments; only returns if error.
    "open", // Open a file; flags indicate read/write; returns an fd (file descriptor).
    "mknod", // Create a device file.
    "unlink", // Remove a file.
    "fstat", // Place info about an open file into *st.
    "link", // Create another name (file2) for the file file1.
    "mkdir", // Create a new directory.
    "chdir", // Change the current directory.
    "dup", // Return a new file descriptor referring to the same file as fd.
    "getpid", // Return the current processors PID.
    "sbrk", // Grow processors memory by n bytes. Returns start of new memory.
    "sleep", // Pause for n clock ticks.
    "uptime", // Return the current time since boot in ticks.
    "ringbuf", // Ringbuf creation/deletion
};

pub fn build(b: *std.build.Builder) !void {
    const target = std.zig.CrossTarget{
        .os_tag = .freestanding,
        .cpu_arch = .riscv64,
        .abi = .none,
    };

    const opts = b.addOptions();
    const use_gdb = b.option(bool, "gdb", "Use gdb") orelse false;
    opts.addOption(bool, "gdb", use_gdb);

    const kernel_linker = "build/linker/kernel.ld";
    const user_linker = "build/linker/user.ld";

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = .{ .path = "src/kernel/start.zig" },
        .target = target,
        .optimize = std.builtin.Mode.ReleaseSmall,
    });
    kernel.addAnonymousModule("common", .{ .source_file = .{ .path = "src/common/mod.zig" } });
    kernel.addCSourceFiles(&kernel_src, &cflags);
    kernel.addIncludePath(.{ .path = "src" });
    kernel.setLinkerScriptPath(.{ .path = kernel_linker });
    kernel.code_model = .medium;
    kernel.strip = false;
    kernel.want_lto = true;
    kernel.single_threaded = true;
    b.installArtifact(kernel);

    const syscall_gen_step = addSyscallGen(b, &syscalls);

    const ulib = b.addStaticLibrary(.{
        .name = "ulib",
        .root_source_file = .{ .path = "src/user/ulib/ulib.zig" },
        .optimize = std.builtin.Mode.ReleaseSafe,
        .target = target,
    });
    ulib.single_threaded = true;
    ulib.addAnonymousModule("common", .{ .source_file = .{ .path = "src/common/mod.zig" } });
    ulib.addCSourceFile(.{ .file = syscall_gen_step.getLazyPath(), .flags = &cflags });
    ulib.addIncludePath(.{ .path = "src" });

    var artifacts = std.ArrayList(*CompileStep).init(b.allocator);
    inline for (user_progs) |prog| {
        const user_prog = blk: {
            if (prog.type == .zig) {
                const src = "src/user/" ++ prog.name ++ ".zig";
                const user_prog = b.addExecutable(.{
                    .name = prog.name,
                    .root_source_file = .{ .path = src },
                    .optimize = std.builtin.Mode.ReleaseSafe,
                    .target = target,
                });
                user_prog.step.dependOn(&ulib.step);
                user_prog.linkLibrary(ulib);
                user_prog.addAnonymousModule("common", .{ .source_file = .{ .path = "src/common/mod.zig" } });
                user_prog.addCSourceFiles(&ulib_z_src, &cflags);
                break :blk user_prog;
            } else {
                const src = "src/user/" ++ prog.name ++ ".c";
                const src_files = &[_][]const u8{src} ++ ulib_c_src;
                const exe_name = "_" ++ prog.name;
                const user_prog = b.addExecutable(.{
                    .name = exe_name,
                    .target = target,
                    .optimize = std.builtin.Mode.ReleaseSmall,
                });
                user_prog.step.dependOn(&ulib.step);
                user_prog.linkLibrary(ulib);
                user_prog.addCSourceFiles(src_files, &cflags);
                break :blk user_prog;
            }
        };
        user_prog.single_threaded = true;
        // user_prog.addCSourceFile(.{ .file = syscall_gen_step.getLazyPath(), .flags = &cflags });
        user_prog.addIncludePath(.{ .path = "src" });
        user_prog.setLinkerScriptPath(.{ .path = user_linker });
        user_prog.code_model = .medium;
        user_prog.step.dependOn(&syscall_gen_step.step);
        b.installArtifact(user_prog);
        try artifacts.append(user_prog);
    }

    const image = installFilesystem(b, artifacts, "fs.img");
    qemuRun(b, kernel, image, use_gdb);
}

/// Output filesystem image determined by filename
pub fn installFilesystem(
    b: *std.Build,
    artifacts: std.ArrayList(*CompileStep),
    dest_filename: []const u8,
) *MakeFilesystemStep {
    const img = addMakeFilesystem(b, artifacts, dest_filename);
    b.getInstallStep().dependOn(&img.step);
    return img;
}

pub fn addMakeFilesystem(
    b: *std.Build,
    artifacts: std.ArrayList(*CompileStep),
    dest_filename: []const u8,
) *MakeFilesystemStep {
    return MakeFilesystemStep.create(b, artifacts, dest_filename);
}

pub fn addSyscallGen(
    b: *std.Build,
    data: []const []const u8,
) *SyscallGenStep {
    return SyscallGenStep.create(b, data);
}

pub fn qemuRun(
    b: *std.Build,
    kernel: *CompileStep,
    image: *MakeFilesystemStep,
    use_gdb: bool,
) void {
    if (!b.enable_qemu) return;

    const run_step = RunStep.create(b, "run xv6 step");
    b.getInstallStep().dependOn(&run_step.step);

    const qemu_run_step = QemuRunStep.create(b, kernel, .{
        .image = image,
        .run_step = run_step,
        .use_gdb = use_gdb,
    });
    b.getInstallStep().dependOn(&qemu_run_step.step);
}
