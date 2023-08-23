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
    // "src/kernel/kalloc.c", // Disk device driver.
    // "src/kernel/printf.c", // Disk device driver.
};

const cflags = [_][]const u8{
    "-Wall",
    "-Werror",
    "-Wno-gnu-designator", // workaround for compiler error
    "-fno-omit-frame-pointer",
    "-gdwarf-2",
    "-MD",
    "-ggdb",
    "-ffreestanding",
    "-fno-common",
    "-nostdlib",
    "-mno-relax",
    "-fno-pie",
    "-fno-stack-protector",
    "-Wno-unused-but-set-variable", // workaround for compiler error
};

const user_progs = [_][]const u8{
    // "src/user/forktest.c", // ToDo: build forktest
    "src/user/cat.c",
    "src/user/echo.c",
    "src/user/grep.c",
    "src/user/init.c",
    "src/user/kill.c",
    "src/user/ln.c",
    "src/user/ls.c",
    "src/user/mkdir.c",
    "src/user/rm.c",
    "src/user/sh.c",
    "src/user/stressfs.c",
    "src/user/usertests.c",
    "src/user/grind.c",
    "src/user/wc.c",
    "src/user/zombie.c",
};

const ulib_src = [_][]const u8{
    "src/user/ulib.c",
    "src/user/printf.c",
    "src/user/umalloc.c",
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
    "uptime",
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

    const kernel_linker = "scripts/kernel.ld";
    const user_linker = "scripts/user.ld";

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = .{ .path = "src/kernel/start.zig" },
        .target = target,
        .optimize = std.builtin.Mode.ReleaseSmall,
    });
    kernel.addCSourceFiles(&kernel_src, &cflags);
    kernel.addIncludePath(.{ .path = "src" });
    kernel.setLinkerScriptPath(.{ .path = kernel_linker });
    kernel.code_model = .medium;
    kernel.strip = true;
    b.installArtifact(kernel);

    const syscall_gen_step = addSyscallGen(b, &syscalls);

    var artifacts = std.ArrayList(*CompileStep).init(b.allocator);
    inline for (user_progs) |src| {
        const src_files = &[_][]const u8{src} ++ ulib_src;
        const exe_name = "_" ++ src["src/user/".len .. src.len - 2];
        const user_prog = b.addExecutable(.{
            .name = exe_name,
            .target = target,
            .optimize = std.builtin.Mode.ReleaseSmall,
        });
        user_prog.addCSourceFiles(src_files, &cflags);
        user_prog.addCSourceFile(.{ .file = syscall_gen_step.getLazyPath(), .flags = &cflags });
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
