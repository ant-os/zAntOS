const std = @import("std");

pub fn build(b: *std.Build) void {

    const target: std.Target.Query =  .{
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

    const exe = b.addExecutable(.{
        .name = "antboot2",
        .root_module = loaderModule,
    });

    b.installArtifact(exe);

 

}
