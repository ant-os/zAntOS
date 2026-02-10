//! AntOS Operating System Kernel Main File

// AntOS Kernel

const antos_kernel = @import("root");

const std = @import("std");
const bootboot = @import("bootboot.zig");
const io = @import("io.zig");
const memory = @import("memory.zig");
const pageFrameAllocator = @import("pageFrameAllocator.zig");
const klog = std.log.scoped(.kernel);
const paging = @import("paging.zig");
const heap = @import("heap.zig");
const antstatus = @import("status.zig");
pub const ANTSTATUS = antstatus.ANTSTATUS;
const filesystem = @import("filesystem.zig");
const driverManager = @import("driverManager.zig");
const driverCallbacks = @import("driverCallbacks.zig");
const builtindrv_initrdfs = @import("initrdfs.zig");
const ramdisk = @import("ramdisk.zig");
const resource = @import("resource.zig");
const logger = @import("logger.zig");
const shell = @import("shell/shell.zig");
const gdt = @import("gdt.zig");
const idt = @import("idt.zig");
const bootmem = @import("bootmem.zig");
const arch = @import("arch.zig");
const kpcb = @import("kpcb.zig");
const symbols = @import("debug/elf_symbols.zig");
const ktest = @import("ktest.zig");

pub const Executable = @import("executable.zig");
pub const BlockDevice = @import("blockdev.zig");

const fontEmbedded = @embedFile("font.psf");
const QEMU_DEBUGCON = 0xe9;

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = logger.zig_log,
    .fmt_max_depth = 4,
};

pub noinline fn earlybug(comptime key: anytype) noreturn {
    asm volatile (std.fmt.comptimePrint(
            \\jmp __earlybug_{0s}
            \\__earlybug_{0s}: ud2
            \\jmp __earlybug_{0s}
        ,
            .{@tagName(key)},
        )
        :
        : [caller] "{eax}" (@returnAddress()),
    );

    std.mem.doNotOptimizeAway(@extern(
        *const fn () callconv(.c) noreturn,
        .{ .name = "__earlybug_" ++ @tagName(key) },
    ));

    unreachable;
}

var allocating_wr = std.io.Writer.Allocating.init(heap.allocator);

pub noinline fn kmain() !void {
    // defer heap.dumpSegments();

    // klog.info("Starting zAntOS...", .{});

    // klog.info("Total physical memory of {d} KiB", .{memory.KePhysicalMemorySize() / 1024});

    // pageFrameAllocator.init() catch |e| {
    //     klog.err("Failed to initalize page bitmap: {s}", .{@errorName(e)});
    //     return;
    // };

    // const myPage = try pageFrameAllocator.requestPage();

    // klog.debug("my page: {d} ({x})", .{ myPage, myPage * 0x1000 });

    // klog.debug("Allocated Page: {x}", .{(try pageFrameAllocator.requestPage()) * 0x1000});

    // klog.info("Used Memory: {d}/{d} KiB", .{
    //     pageFrameAllocator.getUsedMemory() / 1024,
    //     memory.KePhysicalMemorySize() / 1024,
    // });

    // klog.info("Free Memory: {d}/{d} KiB", .{
    //     pageFrameAllocator.getFreeMemory() / 1024,
    //     memory.KePhysicalMemorySize() / 1024,
    // });

    // paging.init() catch |e| {
    //     klog.err("Failed to initalize kernel paging: {s}", .{@errorName(e)});
    //     return;
    // };

    // heap.init(1) catch |e| {
    //     klog.err("Failed to initalize kernel heap: {s}", .{@errorName(e)});
    //     return;
    // };

    // klog.info("Parsing initrd...", .{});

    // const initrd: [*]align(1) u8 = @ptrFromInt(bootboot.bootboot.initrd_ptr);
    // var initrd_reader = std.io.Reader.fixed(initrd[0..bootboot.bootboot.initrd_size]);
    // var tar_iter = std.tar.Iterator.init(&initrd_reader, .{
    //     .file_name_buffer = try heap.allocator.alloc(u8, 255),
    //     .link_name_buffer = try heap.allocator.alloc(u8, 255),
    // });

    // var file: std.tar.Iterator.File = undefined;
    // for (0..2) |_| {
    //     file = (try tar_iter.next()) orelse break;
    //     if (std.ascii.endsWithIgnoreCase(file.name, ".text")) {
    //         klog.info("file {s} ({d} bytes): {s}", .{
    //             file.name,
    //             file.size,
    //             try initrd_reader.readAlloc(heap.allocator, file.size),
    //         });
    //     } else {
    //         klog.info("file {s} ({d} bytes): <not a text file>", .{
    //             file.name,
    //             file.size,
    //         });
    //     }

    //     if (initrd_reader.seek == bootboot.bootboot.initrd_size - 1) break;
    // }

    // heap.dumpSegments();

    // var status = ANTSTATUS.err(.invalid_parameter);

    // klog.debug("status: {f}", .{status});
    // klog.debug("zig error: {any}", .{status.intoZigError()});
    // klog.debug("c-style error code: 0x{x}.", .{status.asU64()});
    // klog.debug("casted from int of 0x70..3: {f}", .{ANTSTATUS.fromU64(0x7000000000000003)});

    // klog.info("kernel exe: {any}", .{Executable.kernel()});

    // klog.debug("handle: {any}", .{resource.keAllocateHandle(.directory)});
    // heap.dumpSegments();

    // klog.debug("created com1 connection", .{});

    // klog.debug("int called", .{});

    // asm volatile ("sti");

    // klog.info("Reached end of kmain()", .{});
}

pub const panic = @import("panic.zig").__zig_panic_impl;

// Entry point, called by BOOTBOOT Loader
export fn _start() callconv(.c) noreturn {
    // @setRuntimeSafety(false);
    const log = std.log.scoped(.kernel_init);
    // On BSP if loader is valid:
    // 1. Init COM1 serial
    // 2. find free segment large enough to page bitmap
    // 3. use the page frame alloc to allocate the KPCB for the BSP.
    // 4. initalize basic idt in KPCB.
    // 5. initalize paging and update struct pointers.
    // Last: Start shell.

    logger.init() catch unreachable;

    bootmem.init() catch |e| {
        log.err("failed to initalize bootmem: {s}", .{@errorName(e)});
        arch.halt_cpu();
    };

    kpcb.early_init() catch |e| {
        log.err("failed to initalize KPCB for BSP: {s}", .{@errorName(e)});
        arch.halt_cpu();
    };

    std.debug.assert(kpcb.local.canary == kpcb.CANARY);

    symbols.init() catch |e| {
        log.err("failed to initalize stacktraces: {s}", .{@errorName(e)});
        arch.halt_cpu();
    };

    if (@import("builtin").is_test) ktest.main() catch unreachable;

    klog.debug("kmain() skipped.", .{});
    arch.halt_cpu();
}

comptime { std.testing.refAllDecls(@import("panic.zig")); }