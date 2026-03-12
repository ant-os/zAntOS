//! AntOS Operating System Kernel Main File

// AntOS Kernel

const antos_kernel = @import("kmod");

const std = @import("std");
const io = @import("io.zig");

const klog = std.log.scoped(.kernel);

const paging = @import("mm/paging.zig");
const bootmem = @import("mm/bootmem.zig");
const pfmdb = @import("mm/pfmdb.zig");
const pframe_alloc = @import("mm/pframe_alloc.zig");
const vmm = @import("mm/vmm.zig");
const heap = @import("mm/heap.zig");
const syspte = @import("mm/syspte.zig");
const mm = @import("mm.zig");

const ob = @import("ob/object.zig");
const vfs = @import("ob/vfs.zig");

const antboot = @import("bootloader");
const bootloader = @import("bootloader.zig");

const zuacpi_bind = @import("acpi/zuacpi.zig");
const zuacpi = @import("zuacpi");
const uacpi = zuacpi.uacpi;
const pci = @import("pci.zig");

const irql = @import("interrupts/irql.zig");
const interrupts = @import("interrupts.zig");

const Driver = @import("io/Driver.zig");
const Device = @import("io/Device.zig");
const Irp = @import("io/Irp.zig");

const Scheduler = @import("scheduler.zig");
const Process = @import("scheduling/process.zig");

const Mutex = @import("sync/Mutex.zig");

const pic = @import("pic.zig");
const apic = @import("apic.zig");
const tsc = @import("tsc.zig");
const cpuid = @import("cpuid.zig");

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

pub const zuacpi_options: @import("zuacpi").Options = .{ .allocator = heap.allocator };

export fn antkInitalizeSystem(_: ?*anyopaque) callconv(arch.cc_unaligned) noreturn {
    klog.info("reached antkInitalizeSystem().", .{});
    init() catch |e| std.debug.panic("init failed with error: {s}", .{@errorName(e)});
    arch.halt_cpu();
}

pub fn gasWrite(comptime T: type, addr: zuacpi.Gas, value: T) !void {
    if (@bitSizeOf(T) != addr.register_bit_width) return error.MismatchedBitWidth;
    switch (addr.address_space) {
        .system_memory => {
            const memaddr = mm.PhysicalAddress{ .uint = addr.address.system_memory };
            const mapping: *volatile T = @ptrCast(try mm.map(
                memaddr,
                @sizeOf(T),
                .{ .writable = true, .write_through = true },
            ));
            mapping.* = value;
            try mm.unmap(.of(@volatileCast(mapping)), @sizeOf(T));
        },
        .system_io => {
            const port: u16 = @intCast(addr.address.system_io);
            io.writeAny(T, port, value);
        },
        else => std.debug.panic("unsupported address space for write: {s}", .{@tagName(addr.address_space)}),
    }
}

pub noinline fn init() !void {
    const log = klog;

    var r: u64 = 0;
    std.mem.doNotOptimizeAway(@import("acpi/shims.zig").uacpi_kernel_get_rsdp(&r));

    //  apic.init() catch unreachable;

    log.info("temporary mapping virtaddr: {any}", .{mm.map(
        .{ .uint = 0xAAAA0000 },
        32,
        .{},
    )});

    try heap.lateInit();
    try uacpi.initialize(.{});
    try pci.init();
    pic.remapAndDisable();
    try apic.init();
    try apic.timer.init();

    asm volatile ("sti");

    //const mymutex = try Mutex.new();

    log.info("stalling for 1s...", .{});
    tsc.stall(1_000_000);

    log.info("cpuid(.freq_1) = {any}", .{cpuid.cpuid(cpuid.freq_1)});
    log.info("bootloader found that it is: {d}ns per cycle for the tsc", .{bootloader.info.us_per_cycle});

    const fadt = try uacpi.tables.table_fadt();
    log.info("reset reg: {any}, reset value: {any}", .{ fadt.reset_reg, fadt.reset_value });
    // try gasWrite(u8, fadt.reset_reg, fadt.reset_value);

    log.info("cpuid query(leaf=1): {any}", .{cpuid.cpuid(.cpu_info_and_features)});

    log.info("dumping info about the first process and it's threads.", .{});
    try Process.initialSystemProcess.dump(logger.writer(), true);

    // uacpi.namespace.get_root().for_each_child_simple(&struct {
    //     pub fn call(_: ?*anyopaque, node: *uacpi.namespace.NamespaceNode, depth: u32) callconv(.c) uacpi.namespace.IterationDecision {
    //         log.info("{d}, node {s} of type {any}", .{depth, node.generate_absolute_path() orelse "<???>", node.node_type()});
    //         return .@"continue";
    //     }
    // }.call, null) catch unreachable;

    try testing_();

    if (@import("builtin").is_test) ktest.main() catch unreachable;
    log.info("END", .{});
}

fn handleDispatch(_: *interrupts.TrapFrame, _: ?*anyopaque) callconv(.c) bool {
    kpcb.current().scheduler.yield_ = true;
    return true;
}

// Entry point, called by Loader
export fn antkStartupSystem(info: *antboot.BootInfo) callconv(arch.cc) noreturn {
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

    bootloader.info = info;

    log.info("boot info: {any}", .{info});

    bootmem.init() catch |e| {
        log.err("failed to initalize bootmem alloc: {s}", .{@errorName(e)});
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
    heap.init(32) catch unreachable;
    syspte.init() catch unreachable;
    tsc.init() catch unreachable;
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
        antkInitalizeSystem,
        null,
    ) catch |e| std.debug.panic(
        "failed to spawn stage2 init thread: {s}",
        .{@errorName(e)},
    );
    initThread.name = "Init";

    asm volatile ("int $0x20");
    unreachable;
}

var global_mutex: ?*Mutex = null;

pub fn threadFunc(_: ?*anyopaque) callconv(.c) noreturn {
    klog.info("Thread {d}: acquire(lock)", .{Scheduler.safeCurrentThreadId().uint});

    global_mutex.?.lock() catch unreachable;

    klog.info("Thread {d}: lock acquired", .{Scheduler.safeCurrentThreadId().uint});

    tsc.stall(10000);

    global_mutex.?.unlock();

    klog.info("Thread {d}: lock released", .{Scheduler.safeCurrentThreadId().uint});

    while (true) {
        std.atomic.spinLoopHint();
    }
}

pub fn testing_() !void {
    try logger.newline();

    const mydrv = try Driver.create("example", &.{"ANT0000"});
    mydrv.setCallback(
        .example,
        @ptrCast(&struct {
            pub fn call(self: *Irp, params: *std.meta.TagPayloadByName(Irp.MajorFunction, "example"), _: ?*anyopaque) anyerror!void {
                klog.debug("callback invoked, irp = {any} and params = {any}", .{ self, params });
            }
        }.call),
    );

    klog.debug("my driver: {any}", .{mydrv});

    const mydev = try Device.create("test device", null);
    mydev.driver = mydrv;

    klog.debug("my device: {any}", .{mydev});

    const irp = try Irp.create();
    try irp.addEntry(
        mydev,
        .{
            .example = .{ .a = 1234 },
        },
        null,
    );

    klog.debug("{any} (expecting void)", .{irp.executeSingle()});

    {
        const oldIrql = irql.raise(.deferred);
        defer irql.update(oldIrql);

        const threadA = try Process.initialSystemProcess.spawnThread(threadFunc, null);
        threadA.name = "Test";

        global_mutex = try Mutex.new();
        try global_mutex.?.lock();

        klog.info("testing mutex and scheduler... note: lock is owned by init but unlocking at idx=10", .{});
    }

    for (0..21) |i| {
        tsc.stall(1000);
        if (i == 10) global_mutex.?.unlock();
        try logger.println("work work.... idx={d}", .{i});
    }

    asm volatile ("cli");

    try vfs.init();

    try vfs.attach("//Devices/GLOBALROOT/TestDevice", &mydev.header);

    const vfsdev: *Device = @fieldParentPtr(
        "header",
        (try vfs.resolve("//Devices/GLOBALROOT/TestDevice")) orelse @panic("no object bound to vfs path"),
    );

    klog.info("result translated to device object: {any}", .{vfsdev});

    arch.halt_cpu();
}

export fn mythreadfunc(ctx: ?*anyopaque) callconv(arch.cc) noreturn {
    _ = ctx;
    klog.info("now we are a real thread!", .{});

    klog.debug("current thread id is {any}", .{kpcb.local.scheduler.current_thread.?.id});

    @breakpoint();

    Scheduler.yield();

    klog.info("now we are back after yield()...", .{});

    while (true) {
        std.atomic.spinLoopHint();
    }
}

fn testcb(_: *interrupts.TrapFrame, _: ?*anyopaque) callconv(.c) bool {
    klog.info("test irq callback invoked...", .{});
    return true;
}

pub noinline fn software_int(comptime int: u8) void {
    asm volatile (std.fmt.comptimePrint("int $0x{x}", .{int}));
}

comptime {
    std.testing.refAllDecls(@import("panic.zig"));
}
