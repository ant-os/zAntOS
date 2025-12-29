const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.addModule("zantos-kernel", .{
        .strip = false,
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
        .code_model = .kernel,
        .red_zone = false,
    });
    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_module = module,
        .version = .{ .major = 0, .minor = 3, .patch = 1, .pre = "unstable" },
    });

    //  kernel.setLinkerScript(b.path("src/link.ld"))

    kernel.linker_script = b.path("src/link.ld");
    // kernel.strip = true;
    b.verbose = true;
    b.verbose_link = true;
    //try kernel.force_undefined_symbols.put("bootboot", undefined);
    b.installArtifact(kernel);
}
