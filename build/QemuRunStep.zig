const std = @import("std");
const mem = std.mem;
const Build = std.Build;
const Step = Build.Step;
const CompileStep = Build.CompileStep;
const MakeFilesystemStep = @import("MakeFilesystemStep.zig");
const RunStep = Build.RunStep;

const QemuRunStep = @This();

step: Step,

/// The kernel (executable) to be run by this step
kernel: *CompileStep,

/// The filesystem image for the os
image: *MakeFilesystemStep,

run_step: *RunStep,

/// Whether to use GDB or not
use_gdb: bool,

pub const Options = struct {
    image: *MakeFilesystemStep,
    run_step: *RunStep,
    use_gdb: bool = false,
};

pub fn create(
    owner: *Build,
    kernel: *CompileStep,
    options: Options,
) *QemuRunStep {
    std.debug.assert(kernel.kind == .exe);
    const self = owner.allocator.create(QemuRunStep) catch @panic("OOM");

    self.* = .{
        .step = Step.init(.{
            .id = .custom,
            .name = "Run xv6 os with qemu",
            .owner = owner,
            .makeFn = make,
        }),
        .kernel = kernel,
        .image = options.image,
        .run_step = options.run_step,
        .use_gdb = options.use_gdb,
    };

    self.run_step.step.dependOn(&self.step);
    self.step.dependOn(&self.kernel.step);
    self.step.dependOn(&self.image.step);

    return self;
}

fn make(step: *Step, prog_node: *std.Progress.Node) !void {
    _ = prog_node;
    const self = @fieldParentPtr(QemuRunStep, "step", step);

    if (!self.step.owner.enable_qemu) {
        return;
    }

    var argv_list = std.ArrayList([]const u8).init(self.step.owner.allocator);
    defer argv_list.deinit();

    try argv_list.appendSlice(&[_][]const u8{
        "qemu-system-riscv64",
        "-machine",
        "virt",
        "-bios",
        "none",
        "-m",
        "128M",
        "-smp",
        "3",
        "-nographic",
        "-global",
        "virtio-mmio.force-legacy=false",
        "-device",
        "virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0",
    });
    if (self.use_gdb) {
        try argv_list.appendSlice(&[_][]const u8{
            "-s",
            "-S",
        });
    }

    const kernel_path = self.kernel.getOutputSource().getPath(self.step.owner);
    try argv_list.appendSlice(&[_][]const u8{
        "-kernel",
        kernel_path,
    });

    const image_path = self.image.getOutputSource().getPath(self.step.owner);
    var drive_arg = try mem.concat(self.step.owner.allocator, u8, &[_][]const u8{
        "file=",
        image_path,
        ",if=none,format=raw,id=x0",
    });
    defer self.step.owner.allocator.free(drive_arg);

    try argv_list.appendSlice(&[_][]const u8{
        "-drive",
        drive_arg,
    });
    self.run_step.addArgs(argv_list.items);
}
