const std = @import("std");

fn target_features(query: *std.Target.Query) !void {
    query.cpu_model = .{ .explicit = std.Target.Cpu.Model.generic(query.cpu_arch.?) };
    switch (query.cpu_arch.?) {
        .x86_64 => {
            const Features = std.Target.x86.Feature;

            query.cpu_features_add.addFeature(@intFromEnum(Features.soft_float));

            query.cpu_features_sub.addFeature(@intFromEnum(Features.mmx));
            query.cpu_features_sub.addFeature(@intFromEnum(Features.sse));
            query.cpu_features_sub.addFeature(@intFromEnum(Features.sse2));
            query.cpu_features_sub.addFeature(@intFromEnum(Features.avx));
            query.cpu_features_sub.addFeature(@intFromEnum(Features.avx2));
        },
        else => return error.invalid_arch,
    }
}

pub fn build(b: *std.Build) !void {
    const arch = .x86_64;
    var selected_target: std.Target.Query = .{
        .abi = .none,
        .os_tag = .freestanding,
        .cpu_arch = arch,
    };
    try target_features(&selected_target);
    const target = b.resolveTargetQuery(selected_target);
    const optimize = b.standardOptimizeOption(.{});
    const kmod = b.addModule("zantos-kernel", .{
        .strip = false,
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .kernel,
        .red_zone = false,
        .stack_check = true,
        .omit_frame_pointer = false,
    });
    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_module = kmod,
        .use_llvm = true,
        .use_lld = true,
        .version = .{ .major = 0, .minor = 3, .patch = 1, .pre = "unstable" },
    });

    const options = b.addOptions();
    options.addOption(
        []const u8,
        "image_name",
        b.option(
            []const u8,
            "image-name",
            "The name of the kernel image in the final system.",
        ) orelse "AntOSKrnl.bin",
    );
    kmod.addOptions("options", options);
    kmod.addImport("kmod", kmod);

    //  kernel.setLinkerScript(b.path("src/link.ld"))

    kernel.linker_script = b.path("src/link.ld");
    kernel.stack_size = 0x1000;

    // kernel.strip = true;
    b.verbose = true;
    b.verbose_link = true;
    //try kernel.force_undefined_symbols.put("bootboot", undefined);

    b.installArtifact(kernel);

    b.verbose_cc = true;
    b.verbose_air = true;
    
    const ktest = b.addTest(.{
        .name = "ktest",
        .root_module = kmod,
        .use_lld = true,
        .use_llvm = true,
        
        .test_runner = .{

            .mode = .simple,
            .path = b.path("src/test_main.zig"),
        },
    });

    ktest.linker_script = b.path("src/link.ld");

    b.installArtifact(ktest);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = kernel.getEmittedDocs(),
        .install_dir = .{ .custom = "../output/docs" },
        .install_subdir = "kernel-internal",
    });

    const docs_step = b.step("docs", "Install docs into zig-out/docs");
    docs_step.dependOn(&install_docs.step);

    b.install_tls.step.dependOn(docs_step);
}
