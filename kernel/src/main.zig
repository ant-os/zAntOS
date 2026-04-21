//! AntOS Operating System Kernel Main Sourcefile

// self-import, std, builtins, default logger.
const antos_kernel = @import("kmod");  
const std = @import("std");
const builtin = @import("builtin");
const klog = std.log.scoped(.kernel);

// ==== TODO ====
// Cleanup these imports and re-exports
// to just expose subsystems and not also a
// selection of modules of different subsystems.
pub const portio = @import("hal/portio.zig");
pub const paging = @import("mm/paging.zig");
pub const bootmem = @import("mm/bootmem.zig");
pub const pfmdb = @import("mm/pfmdb.zig");
pub const pframe_alloc = @import("mm/pframe_alloc.zig");
pub const vmm = @import("mm/vmm.zig");
pub const heap = @import("mm/heap.zig");
pub const syspte = @import("mm/syspte.zig");
pub const mm = @import("mm/mm.zig");
pub const ob = @import("ob/object.zig");
pub const vfs = @import("ob/vfs.zig");
pub const antboot_external = @import("bootloader");
pub const antboot = @import("utils/antboot.zig");
pub const zuacpi_bind = @import("hal/acpi/zuacpi.zig");
pub const zuacpi = @import("zuacpi");
pub const uacpi = zuacpi.uacpi;
pub const pci = @import("hal/pci.zig");
pub const hal = @import("hal/hal.zig");
pub const interrupts = @import("hal/interrupts.zig");
pub const Driver = @import("io/Driver.zig");
pub const Device = @import("io/Device.zig");
pub const Irp = @import("io/Irp.zig");
pub const Scheduler = @import("sched/scheduler.zig");
pub const Process = @import("sched/process.zig");
pub const Thread = @import("sched/thread.zig");
pub const Mutex = @import("ke/sync/Mutex.zig");
pub const apic = @import("hal/apic/apic.zig");
pub const tsc = @import("hal/arch/tsc.zig");
pub const cpuid = @import("hal/cpuid.zig");
pub const antk = @import("antk/antk.zig");
pub const antstatus = @import("antk/status.zig");
pub const ANTSTATUS = antstatus.ANTSTATUS;
pub const logger = @import("debug/logger.zig");
pub const shell = @import("debug/shell/shell.zig");
pub const arch = @import("hal/arch/arch.zig");
pub const kpcb = @import("ke/kpcb.zig");
pub const ktest = @import("tests/framework.zig");
pub const symbols = @import("debug/elf_symbols.zig");
pub const HardwareIo = @import("io/abstracthw.zig");

// zig panic handler and std options
pub const panic = @import("ke/panic.zig")._zig_panic_impl;
pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = logger._zig_log_impl,
    .fmt_max_depth = 4,
};

/// Entry point, called by Loader(antboot).
/// This does early setup of core subsystems(mm, bootldr abstraction, hal, logger, etc.).
/// then creates the "System" process and the first real thread
/// with `antkInitializeSystem`(stage2 init, located in `ke/init.zig`) as the entrypoint.
export fn antkStartupSystem(info: *antboot_external.BootInfo) callconv(arch.cc) noreturn {
    logger.init() catch {
        // should never happen!!!
        // but incase it does fail bail out in debug mode,
        // and halt the cpu in release.
        if (builtin.mode == .Debug) {
            asm volatile (
                \\movq $0xDEAD1, %%rax
                \\int $0xFF
            );
        }
        arch.halt_cpu();
    };

    const log = std.log.scoped(.kernel_init);
    antboot.info = info;

    log.info("boot info: {any}", .{info});

    bootmem.init() catch |e| {
        log.err("failed to initalize bootmem alloc: {s}", .{@errorName(e)});
        arch.halt_cpu();
    };

    @import("hal/arch/gdt.zig").init();
    @import("hal/arch/idt.zig").init();

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
    heap.init(32) catch unreachable;
    syspte.init() catch unreachable;
    tsc.init() catch unreachable;
    ob.initObjectTypes() catch @panic("failed to create object types");
    kpcb.current().scheduler.init() catch unreachable;

    _ = Process.createInitialSystemProcess() catch |e| std.debug.panic(
        "failed to create initial system process: {s}",
        .{@errorName(e)},
    );
    const idleThread = Process.initialSystemProcess.createThread(
        &Scheduler.__thread_idle,
        null,
    ) catch |e| std.debug.panic(
        "failed to create idle thread: {s}",
        .{@errorName(e)},
    );
    idleThread.name = "Idle";
    idleThread.priority = .lowest;
    idleThread.setState(.ready);
    Scheduler.setIdleThread(idleThread);

    const dispatchIrq = interrupts.create(.dispatch) catch |e| std.debug.panic(
        "failed to create dispatch interrupt: {s}",
        .{@errorName(e)},
    );
    dispatchIrq.attach(&handleDispatch, null);
    kpcb.current().irq_router.register(dispatchIrq) catch |e| std.debug.panic(
        "failed to register dispatch interrupt: {s}",
        .{@errorName(e)},
    );

    // finally enable the scheduler on the BSP(current core).
    kpcb.current().scheduler.setEnabled(true);

    const initThread = Process.initialSystemProcess.spawnThread(
        @import("ke/init.zig").antkInitalizeSystem,
        null,
    ) catch |e| std.debug.panic(
        "failed to spawn stage2 init thread: {s}",
        .{@errorName(e)},
    );
    initThread.name = "Init";

    // do an `int 0x20` to call into the scheduler.
    // FIXME: Don't hardcode this.
    software_int(0x20);
    unreachable;
}

fn handleDispatch(_: *interrupts.TrapFrame, _: ?*anyopaque) callconv(.c) bool {
    kpcb.current().scheduler.yield_ = true;
    return true;
}

pub noinline fn software_int(comptime int: u8) void {
    asm volatile (std.fmt.comptimePrint("int $0x{x}", .{int}));
}

pub const zuacpi_options: @import("zuacpi").Options = .{
    .allocator = heap.allocator,
};
