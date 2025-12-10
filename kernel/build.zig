const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.addModule("zantos-kernel", .{
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    const kernel = b.addExecutable(.{ .name = "kernel", .root_module = module, .version = .{ .major = 0, .minor = 3, .patch = 0, .pre = "unstable" } });
    kernel.linker_script = b.path("src/link.ld");
    // kernel.strip = true;
    b.installArtifact(kernel);
}
