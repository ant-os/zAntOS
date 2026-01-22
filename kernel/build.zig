const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.addModule("zantos-kernel", .{
        .strip = false,
        .root_source_file = b.path("src/main.zig"),
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

    const install_docs = b.addInstallDirectory(.{
        .source_dir = kernel.getEmittedDocs(),
        .install_dir = .{ .custom = "../output/docs" },
        .install_subdir = "kernel-internal",
    });

    const docs_step = b.step("docs", "Install docs into zig-out/docs");
    docs_step.dependOn(&install_docs.step);

    b.install_tls.step.dependOn(docs_step);
}
