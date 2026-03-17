const std = @import("std");
const dimmer = @import("dimmer");

const ImageBuilder = dimmer.BuildInterface;
const FilesystemBuilder = ImageBuilder.FileSystemBuilder;
const Build = std.Build;

pub const Install = struct {
    kernel: Build.LazyPath,
    loader: Build.LazyPath,
};

pub const SystemrootBuilder = struct {
    updateFiles: *Build.Step.UpdateSourceFiles,

    pub fn install(self: *SystemrootBuilder, path: Build.LazyPath, sub_path: []const u8) void {
        const real = std.mem.concat(
            self.updateFiles.step.owner.allocator,
            u8,
            &.{ "build/systemroot/", sub_path },
        ) catch @panic("OOM");
        self.updateFiles.addCopyFileToSource(path, real);
    }

    pub fn dependOn(self: *SystemrootBuilder, step: *Build.Step) void {
        self.updateFiles.step.dependOn(step);
    }

    pub fn installBinary(self: *SystemrootBuilder, exe: *Build.Step.Compile, sub_path: []const u8) void {
        self.updateFiles.step.dependOn(&exe.step);
        self.install(exe.getEmittedBin(), sub_path);
    }
};

pub fn build(b: *Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const kernelPath = b.option(
        []const u8,
        "kernel-path",
        "set the kernel path relative to systemroot",
    ) orelse "AntOsKrnl.elf";

    //

    const buildStep = b.getInstallStep();
    const runStep = b.step("run", "run the os using qemu");

    const bootloader = b.dependency("bootloader", .{
        .optimize = optimize,
    });

    const kernel = b.dependency("kernel", .{
        .optimize = optimize,
    });

    var sysrootBuilder: SystemrootBuilder = .{ .updateFiles = b.addUpdateSourceFiles() };

    const systemroot = b.path("build/systemroot");
    systemroot.addStepDependencies(&sysrootBuilder.updateFiles.step);

    const osloader = bootloader.artifact("efi-osloader");
    const kernelbin = kernel.artifact("kernel");

    {
        const template = try std.fs.cwd().readFileAlloc(b.allocator, "bootloader/boot.toml.template", 0xFFFF);
        defer b.allocator.free(template);

        const _1 = std.mem.replaceOwned(
            u8,
            b.allocator,
            template,
            "$$KERNEL_RPATH$$",
            kernelPath,
        ) catch @panic("OOM");

        defer b.allocator.free(_1);

        const _2 = std.mem.replaceOwned(u8, b.allocator, _1, "$$KERNEL_VERSION$$", "0.1") catch @panic("OOM");

        const writer = b.addWriteFiles();
        const tmp = writer.add("boot.toml", _2);
        sysrootBuilder.install(tmp, "boot.toml");
        sysrootBuilder.dependOn(&writer.step);
        buildStep.dependOn(&writer.step);
    }

    sysrootBuilder.installBinary(osloader, "Boot/antboot.efi");
    sysrootBuilder.installBinary(kernelbin, kernelPath);

    var imgBuilder = ImageBuilder.init(b, b.dependencyFromBuildZig(dimmer, .{}));
    var rootfs: ImageBuilder.FileSystemBuilder = .init(b);

    rootfs.copyFile(osloader.getEmittedBin(), "//EFI/AntOS/antboot.efi");
    rootfs.copyFile(osloader.getEmittedBin(), "//EFI/BOOT/BOOTX64.EFI");
    rootfs.copyDirectory(systemroot, "//AntOS/");

    const imageContent: ImageBuilder.Content = .{
        .gpt_part_table = .{
            .partitions = &.{
                ImageBuilder.GptPartTable.Partition{
                    .type = .{ .name = .@"efi-system" },
                    .name = "EFI System Partition",
                    .offset = 0x5000,
                    .data = .{
                        .vfat = .{
                            .format = .fat32,
                            .label = "AntOS_ESP",
                            .tree = rootfs.finalize(),
                        },
                    },
                },
            },
        },
    };

    const image = imgBuilder.createDisk(34 * ImageBuilder.MiB, imageContent);
    image.addStepDependencies(&sysrootBuilder.updateFiles.step);

    const copyOutputs = b.addUpdateSourceFiles();

    const imagePath = "output/x86_64/zAntOS-efi.img";

    copyOutputs.addCopyFileToSource(image, imagePath);
    copyOutputs.step.dependOn(&sysrootBuilder.updateFiles.step);
    _ = try copyOutputs.step.addDirectoryWatchInput(systemroot);

    buildStep.dependOn(&copyOutputs.step);

    const qemuDebug = b.option(
        []const u8,
        "qemu-debug",
        "add certain debug options to qemu",
    ) orelse "cpu_reset";

    const qemuNoreboot = b.option(
        bool,
        "qemu-noreboot",
        "stop qemu from rebooting",
    ) orelse false;

    const ovmfPath = b.option([]const u8, "ovmf-path", "path to ovmf uefi firmware") orelse "/usr/share/ovmf/OVMF.fd";

    const qemuNographic = b.option(
        bool,
        "qemu-nographic",
        "enable or disable graphics for qemu",
    ) orelse true;

    const qemu = b.addSystemCommand(&.{"qemu-system-x86_64"});
    qemu.addArgs(&.{ "-bios", ovmfPath });
    qemu.addArgs(&.{ "-hda", imagePath });
    qemu.addArgs(&.{ "-d", qemuDebug });
    qemu.addArgs(&.{ "-machine", "q35" });
    qemu.addArgs(&.{ "-cpu", "qemu64" });
    if (qemuNographic) qemu.addArg("-nographic");
    if (qemuNoreboot) qemu.addArg("-no-reboot");
    qemu.addArgs(&.{ "-m", "1G" });
    qemu.step.dependOn(buildStep);
    qemu.step.dependOn(&sysrootBuilder.updateFiles.step);

    runStep.dependOn(buildStep);
    runStep.dependOn(&qemu.step);
}
