const std = @import("std");
const dimmer = @import("dimmer");
const ImageBuilder = dimmer.BuildInterface;
const FilesystemBuilder = ImageBuilder.FileSystemBuilder;

pub fn build(b: *std.Build) void {
    const target: std.Target.Query = .{
        .cpu_arch = .x86_64,
        .abi = .none,
        .os_tag = .uefi,
    };

    const optimize = b.standardOptimizeOption(.{});

    const loaderModule = b.addModule("loadermod", .{
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
        .name = "efi-osloader",
        .root_module = loaderModule,
    });

    b.installArtifact(exe);
}
