const std = @import("std");

const klog = std.log.scoped(.kernel);

const pfmdb = @import("../mm/pfmdb.zig");
const pframe_alloc = @import("../mm/pframe_alloc.zig");
const vmm = @import("../mm/vmm.zig");
const heap = @import("../mm/heap.zig");
const syspte = @import("../mm/syspte.zig");
const mm = @import("../mm/../mm/mm.zig");
const ob = @import("../ob/object.zig");
const vfs = @import("../ob/vfs.zig");
const antboot_external = @import("bootloader");
const antboot = @import("../utils/antboot.zig");
const zuacpi_bind = @import("../hal/acpi/zuacpi.zig");
const zuacpi = @import("zuacpi");
const uacpi = zuacpi.uacpi;
const pci = @import("../hal/pci.zig");
const hal = @import("../hal/hal.zig");
const portio = @import("../hal/portio.zig");
const interrupts = @import("../hal/interrupts.zig");
const Driver = @import("../io/Driver.zig");
const Device = @import("../io/Device.zig");
const Irp = @import("../io/Irp.zig");
const Scheduler = @import("../sched/scheduler.zig");
const Process = @import("../sched/process.zig");
const Mutex = @import("../ke/sync/Mutex.zig");
const apic = @import("../hal/apic/apic.zig");
const tsc = @import("../hal/arch/tsc.zig");
const cpuid = @import("../hal/cpuid.zig");
const antk = @import("../antk/antk.zig");
const antstatus = @import("../antk/status.zig");
pub const ANTSTATUS = antstatus.ANTSTATUS;
const logger = @import("../debug/logger.zig");
const shell = @import("../debug/shell/shell.zig");
const arch = @import("../hal/arch/arch.zig");
const kpcb = @import("../ke/kpcb.zig");
const ktest = @import("../tests/framework.zig");
const symbols = @import("../debug/elf_symbols.zig");

pub noinline fn init() !void {
    const log = klog;

    var r: u64 = 0;
    std.mem.doNotOptimizeAway(@import("../hal/acpi/shims.zig").uacpi_kernel_get_rsdp(&r));

    //  apic.init() catch unreachable;

    log.info("temporary mapping virtaddr: {any}", .{mm.map(
        .{ .uint = 0xAAAA0000 },
        32,
        .{},
    )});

    try heap.lateInit();
    try uacpi.initialize(.{});
    try pci.init();
    hal.pic.remapAndDisable();
    try apic.init();
    try apic.timer.init();

    asm volatile ("sti");

    //const mymutex = try Mutex.new();

    log.info("stalling for 1s...", .{});
    tsc.stall(1_000_000);

    log.info("cpuid(.freq_1) = {any}", .{cpuid.cpuid(cpuid.freq_1)});
    log.info("bootloader found that it is: {d}ns per cycle for the tsc", .{antboot.info.us_per_cycle});

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

    try logger.newline();

    const mydev = try Device.create("test device", null);

    klog.debug("my device: {any}", .{mydev});

    {
        const oldIrql = hal.raise(.deferred);
        defer hal.update(oldIrql);

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

    try vfs.attach("//Devices/GLOBALROOT/TestDevice", @ptrCast(mydev));

    const vfsdev: *Device = try ob.referenceKnownObject(
        try vfs.resolve("//Devices/GLOBALROOT/TestDevice") orelse @panic("no object bound to vfs path"),
        Device,
    );

    klog.info("result translated to device object: {any}", .{vfsdev});

    const newarea = try vmm.Area.allocate(
        1,
        0xFFFF_F010_0000_0000,
        0xFFFF_F800_0000_0000,
        .{ .writable = true },
        .{ .string = "cDRVEXEI".* },
    );

    klog.info(
        "MmCreateArea(): area of 0x{x}..0x{x}, backing frames = {d}, tagged {s}",
        .{ newarea.start, newarea.end, newarea.backing_frame_count, newarea.tag.string },
    );

    for (antboot.info.driver_images[0..antboot.info.preloaded_drivers]) |drv| {
        try loadBootDriver(drv);
    }

    try logger.newline();

    try uacpi.namespace_load();

    uacpi.namespace.get_root().for_each_child(
        &struct {
            pub fn call(_: ?*anyopaque, node: *uacpi.namespace.NamespaceNode, depth: u32) callconv(.c) uacpi.namespace.IterationDecision {
                if ((node.node_type() catch return .@"continue") != .device) return .@"continue";

                var hid: *IdString = undefined;
                if (uacpi_eval_hid(node, &hid) != .ok) return .@"continue";
                defer uacpi_free_id_string(hid);

                klog.info("{s}, hid={s}, depth={d}", .{
                    node.generate_absolute_path() orelse "???",
                    hid.bytes[0..hid.size],
                    depth,
                });
                return .@"continue";
            }
        }.call,
        null,
        1 << @intFromEnum(uacpi.ObjectType.device),
        @bitCast(@as(i32, -1)),
        null,
    ) catch unreachable;

    if (@import("builtin").is_test) ktest.main() catch unreachable;
    log.info("END", .{});
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

extern fn uacpi_free_id_string(id: *IdString) callconv(.c) void;

extern fn uacpi_eval_hid(
    node: *uacpi.namespace.NamespaceNode,
    out_id: **IdString,
) callconv(.c) uacpi.uacpi_status;

const IdString = extern struct {
    size: u32,
    bytes: [*]const u8,
};

pub fn loadBootDriver(image: antboot_external.BootInfo.Image) !void {
    const log = std.log.scoped(.antkdrv);
    const elf = std.elf;

    const imageData = image.base[0..image.size];

    log.debug("loading boot driver named {s} ({d} bytes)", .{
        image.name,
        image.size,
    });

    const elfHdr = std.elf.Header.init(
        @as(*const std.elf.Ehdr, @ptrCast(@alignCast(image.base))).*,
        .little,
    );

    log.debug("elf header: {any}", .{elfHdr});

    const strtabHeader = symbols.section_by_name(&elfHdr, imageData, ".strtab") orelse return error.NoStrtab;
    const symtabHeader = symbols.section_by_name(&elfHdr, imageData, ".symtab") orelse return error.NoSymtab;

    if (symtabHeader.sh_type != elf.SHT_SYMTAB or symtabHeader.sh_entsize != @sizeOf(elf.Sym)) return error.UnsupportedSymbolData;

    log.debug(".symtab header: {any}", .{symtabHeader});

    const numSymbols = symtabHeader.sh_size / @sizeOf(elf.Sym);
    const rawSymbols: [*]elf.Sym = @ptrCast(@alignCast(imageData[symtabHeader.sh_offset..]));
    const driverSymbols = rawSymbols[0..numSymbols];

    const rawSectionHeaders: [*]elf.Shdr = @ptrCast(@alignCast(imageData[elfHdr.shoff..]));
    const sections = rawSectionHeaders[0..elfHdr.shnum];

    var shdrIter = elfHdr.iterateSectionHeadersBuffer(imageData);

    while (try shdrIter.next()) |shdr| {
        if ((shdr.sh_flags & elf.SHF_ALLOC) != 0) {
            if (shdr.sh_size == 0) {
                log.debug("skipping zero size section", .{});
            }

            log.info("section {s} at offset 0x{x}, size of {d} bytes and memory range of 0x{x}..0x{x}", .{
                symbols.section_name(
                    &elfHdr,
                    imageData,
                    shdr.sh_name,
                ) orelse "<no name>",
                shdr.sh_offset,
                shdr.sh_size,
                shdr.sh_flags,
                shdr.sh_type,
            });

            const pages = (mm.PAGE_ALIGN.forward(shdr.sh_size) / 0x1000) + 1;

            const vma = try vmm.Area.allocate(
                pages,
                0xFFFF_F010_0000_0000,
                0xFFFF_F800_0000_0000,
                .{ .writable = true },
                .{ .string = "cDRVEXEI".* },
            );

            const writableHeader: *elf.Shdr = @alignCast(std.mem.bytesAsValue(elf.Shdr, imageData[(elfHdr.shoff + (@sizeOf(elf.Shdr) * (shdrIter.index - 1)))..]));

            writableHeader.sh_addr = vma.start;

            log.debug("vma at 0x{x}", .{vma.start});

            const filesize = if (shdr.sh_type == elf.SHT_NOBITS) 0 else shdr.sh_size;
            const data = imageData[shdr.sh_offset..(shdr.sh_offset + filesize)];

            const memory = vma.asPointer()[0..shdr.sh_size];
            @memset(memory, 0);
            @memcpy(memory.ptr, data);
        }
    }

    var relocsIter = elfHdr.iterateSectionHeadersBuffer(imageData);

    while (try relocsIter.next()) |relocHeader| {
        if (relocHeader.sh_type != elf.SHT_RELA) continue;

        log.info("rela section {s} at offset 0x{x}, size of {d} bytes and memory range of 0x{x}..0x{x}", .{
            symbols.section_name(
                &elfHdr,
                imageData,
                relocHeader.sh_name,
            ) orelse "<no name>",
            relocHeader.sh_offset,
            relocHeader.sh_size,
            relocHeader.sh_flags,
            relocHeader.sh_type,
        });
    

        const numRelocations = relocHeader.sh_size / @sizeOf(elf.Rela);
        const rawRelocations: [*]elf.Rela = @ptrCast(@alignCast(imageData[relocHeader.sh_offset..]));
        const relocs = rawRelocations[0..numRelocations];

        for (relocs) |rela| {
            const symbol = &driverSymbols[rela.r_sym()];
            const rtype: elf.R_X86_64 = @enumFromInt(rela.r_type());
            const targetSection = sections[relocHeader.sh_info];

            log.debug("{any}, sym: {any}", .{rela, symbol});

            const symbolName = (if (symbol.st_type() == elf.STT_SECTION) symbols.sectionNameZ(
                &elfHdr,
                imageData,
                sections[symbol.st_shndx].sh_name,
            ) else symbols.strtabGetZ(
                imageData,
                strtabHeader,
                symbol.st_name,
            )) orelse "<noname>";
            log.debug(
                "relocation of type {any} for symbol {s}+0x{x} with patchsite of 0x{x}",
                .{
                    rtype,
                    symbolName,
                    rela.r_addend,
                    targetSection.sh_addr + rela.r_offset,
                },
            );

            const resolvedSymbol = switch (symbol.st_shndx) {
                elf.SHN_UNDEF => if (antk.AntkResolveKernelSymbol(
                    symbolName,
                )) |func| @intFromPtr(func) else {
                    log.err("undefined symbol {s}", .{symbolName});
                    return error.UndefinedSymbol;
                },
                elf.SHN_ABS => symbol.st_value,
                else => |idx| blk: {
                    const section = &sections[idx];
                    break :blk section.sh_addr + symbol.st_value;
                },
            };
            log.debug("patching with 0x{x}", .{resolvedSymbol + @as(usize, @bitCast(rela.r_addend))});

            switch (rtype) {
                .@"64" => {
                    const patchsite: *align(1) volatile u64 = @ptrFromInt(targetSection.sh_addr + rela.r_offset);
                    patchsite.* = resolvedSymbol + @as(u64, @bitCast(rela.r_addend));
                },
                .@"32" => {
                    const patchsite: *align(1) volatile u32 = @ptrFromInt(targetSection.sh_addr + rela.r_offset);
                    patchsite.* = @truncate(resolvedSymbol + @as(usize, @bitCast(rela.r_addend)));
                },
                else => std.debug.panic("unsupported relocation type {any}", .{rtype}),
            }
        }
    }

    var entry: ?*const @TypeOf(antk.antkDriverEntry) = null;

    for (driverSymbols) |sym| {
        const name = symbols.strtab_get(
            imageData,
            strtabHeader,
            sym.st_name,
        ) orelse continue;

        if (std.mem.eql(u8, name, "AntkDriverEntry")) {
            log.info("entry found:{any}", .{sym});
            entry = @ptrFromInt(switch (sym.st_shndx) {
                elf.SHN_UNDEF => return error.UndefinedEntrypoint,
                elf.SHN_ABS => sym.st_value,
                else => |idx| sections[idx].sh_addr + sym.st_value,
            });
            break;
        }
    }

    const driver = try Driver.create(
        image.name[0..std.mem.len(image.name)],
        &.{"ANT????"},
        entry orelse return error.NoEntryPoint,
    );

    log.info("AntkDriverEntry() returned {d}", .{antk.antkDriverEntry(driver, null)});
    log.info("driver object: {any}", .{driver});

    const testdev = try Device.create("test", null);
    testdev.driver = driver;

    const irp = try Irp.create();
    try irp.addEntry(testdev, .{
        .write = .{
            .Buffer = @ptrCast(@constCast("This is the input buffer")),
            .Offset = 0xAAAA,
        },
    }, null);

    log.info("result of write irp: {any}", .{irp.executeSingle()});
}

fn testcb(_: *interrupts.TrapFrame, _: ?*anyopaque) callconv(.c) bool {
    klog.info("test irq callback invoked...", .{});
    return true;
}

pub export fn antkInitalizeSystem(_: ?*anyopaque) callconv(arch.cc_unaligned) noreturn {
    klog.info("reached antkInitalizeSystem().", .{});
    init() catch |e| std.debug.panic("init failed with error: {s}", .{@errorName(e)});
    arch.halt_cpu();
}
