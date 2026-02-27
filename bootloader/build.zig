const std = @import("std");
const dimmer = @import("dimmer");
const ImageBuilder = dimmer.BuildInterface;

pub fn build(b: *std.Build) void {
    const target: std.Target.Query = .{
        .cpu_arch = .x86_64,
        .abi = .none,
        .os_tag = .uefi,
    };

    const optimize = b.standardOptimizeOption(.{});

    const loaderModule = b.addModule("antos-loader", .{
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(target),
        .optimize = optimize,
        // List of modules available for import in source files part of the
        // root module.
        .imports = &.{},
    });

    const toml = b.dependency("toml", .{});
    const tomlMod = toml.module("toml");

    loaderModule.addImport("toml", tomlMod);

    const exe = b.addExecutable(.{
        .name = "antboot2",
        .root_module = loaderModule,
    });

    b.installArtifact(exe);

    var imgBuilder = ImageBuilder.init(b, b.dependencyFromBuildZig(dimmer, .{}));

    var rootfs: ImageBuilder.FileSystemBuilder = .init(b);

    rootfs.copyFile(exe.getEmittedBin(), "//EFI/BOOT/BOOTX64.EFI");
    rootfs.copyFile(b.path("ant.toml"), "//ant.toml");

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

    const image = imgBuilder.createDisk(33 * ImageBuilder.MiB, imageContent);

    const up = b.addUpdateSourceFiles();

    up.step.dependOn(&exe.step);
    up.addCopyFileToSource(image, "output/efi64.img");

    b.getInstallStep().dependOn(&up.step);
}
