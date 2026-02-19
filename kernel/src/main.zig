//! AntOS Operating System Kernel Main File

// AntOS Kernel

const antos_kernel = @import("kmod");

const std = @import("std");
const bootboot = @import("bootboot.zig");
const io = @import("io.zig");

const klog = std.log.scoped(.kernel);

const paging = @import("mm/paging.zig");
const bootmem = @import("mm/bootmem.zig");
const pfmdb = @import("mm/pfmdb.zig");
const pframe_alloc = @import("mm/pframe_alloc.zig");
const vmm = @import("mm/vmm.zig");
const heap = @import("mm/heap.zig");

const irql = @import("interrupts/irql.zig");
const interrupts = @import("interrupts.zig");

//const heap = @import("heap.zig");
const antstatus = @import("status.zig");
pub const ANTSTATUS = antstatus.ANTSTATUS;
//const filesystem = @import("filesystem.zig");
//const driverManager = @import("driverManager.zig");
//const driverCallbacks = @import("driverCallbacks.zig");
//const builtindrv_initrdfs = @import("initrdfs.zig");
//const ramdisk = @import("ramdisk.zig");
//const resource = @import("resource.zig");
const logger = @import("logger.zig");
const shell = @import("shell/shell.zig");
const gdt = @import("gdt.zig");
const idt = @import("idt.zig");
const arch = @import("arch.zig");
const kpcb = @import("kpcb.zig");
const ktest = @import("ktest.zig");
const symbols = @import("debug/elf_symbols.zig");

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

    gdt.init();
    idt.init();

    kpcb.early_init() catch |e| {
        log.err("failed to initalize KPCB for BSP: {s}", .{@errorName(e)});
        arch.halt_cpu();
    };

    symbols.init() catch |e| {
        log.err("failed to initalize stacktraces: {s}", .{@errorName(e)});
        arch.halt_cpu();
    };

    pfmdb.init() catch unreachable;
    pframe_alloc.init() catch unreachable;
    paging.init() catch unreachable;
    interrupts.init() catch unreachable;

    const earlyPageAlloc = pframe_alloc.allocator(&pframe_alloc.AllocContext{
        .map = pframe_alloc.defaultMapAssumeIdentity,
        .translate = pframe_alloc.defaultTranslateAssumeIdentity,
    });

    var myarray = std.ArrayList(u32).empty;

    myarray.append(earlyPageAlloc, 124) catch unreachable;

    myarray.appendNTimes(earlyPageAlloc, 0xA, 12) catch unreachable;

    log.debug("{any}", .{myarray});

    _ = vmm;

    heap.init(32) catch unreachable;

    pframe_alloc.dumpStats(logger.writer()) catch unreachable;

    var mylock = irql.Lock.init;

    log.debug("IRQL before block: {any}", .{irql.current()});

    {
        mylock.lock();
        defer mylock.unlock();

        // high-irql code
        log.debug("IRQL in block: {any}", .{irql.current()});
    }

    log.debug("vector = 0x{x}", .{interrupts.connect(
        &testcb,
        null,
        .dispatch,
        .currentCpu(),
    ) catch unreachable});

    asm volatile ("int $0x20");

    if (@import("builtin").is_test) ktest.main() catch unreachable;
    logger.println("END", .{}) catch unreachable;

    arch.halt_cpu();
}

fn testcb(frame: *interrupts.TrapFrame, _: ?*anyopaque) callconv(.c) bool {
    logger.println("test callback invoked, frame = {any}", .{frame}) catch unreachable;
    return true;
}

pub noinline fn software_int(comptime int: u8) void {
    asm volatile (std.fmt.comptimePrint("int $0x{x}", .{int}));
}

comptime {
    std.testing.refAllDecls(@import("panic.zig"));
}
