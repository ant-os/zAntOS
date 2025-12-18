const std = @import("std");
const klog = std.log.scoped(.kernel_paging);
const bootboot = @import("bootboot.zig");
const pfm = @import("pageFrameAllocator.zig");

pub inline fn isCanonical(addr: usize) bool {
    return (addr >> 48) == 0x0 or (addr >> 48) == std.math.maxInt(u16);
}

/// Index in the PML4 used by the recursive page table, e.g. that points to the PML4 itself.
const RECURSIVE_ENTRY_INDEX = 510;

const PageAccessor = struct {
    pml4: u9 = RECURSIVE_ENTRY_INDEX,
    pdp: u9 = RECURSIVE_ENTRY_INDEX,
    pd: u9 = RECURSIVE_ENTRY_INDEX,
    pt: u9 = RECURSIVE_ENTRY_INDEX,

    pub inline fn asAddr(self: @This()) usize {
        const signext = (@as(usize, self.pml4 >> 8) * 0xFFFF) << 48;
        const shiftedPML4 = @as(usize, self.pml4) << 39;
        const shiftedPDP = @as(usize, self.pdp) << 30;
        const shiftedPD = @as(usize, self.pd) << 21;
        const shiftedPT = @as(usize, self.pt) << 12;

        return signext | shiftedPML4 | shiftedPDP | shiftedPD | shiftedPT;
    }

    pub inline fn asPointer(comptime T: type, self: @This()) *T {
        return @ptrFromInt(PageAccessor.asAddr(self));
    }

    pub inline fn fromAddrAligned(addr: [*]align(0x1000) const u8) @This() {
        const raw_addr = @intFromPtr(addr) >> 12;

        if (!isCanonical(@intFromPtr(addr)))
            klog.warn("Virtual addresse 0x{x} is not canonical, upper bits will be discarded.", .{raw_addr});

        return .{
            .pml4 = @truncate(raw_addr >> 27),
            .pdp = @truncate(raw_addr >> 18),
            .pd = @truncate(raw_addr >> 9),
            .pt = @truncate(raw_addr),
        };
    }

    pub inline fn fromAddr(addr: [*]const u8) @This() {
        return fromAddrAligned(alignToPage(addr));
    }
};

pub inline fn sum(comptime T: type, values: anytype, start: T) T {
    const ValuesType = @TypeOf(values);
    const values_ty = @typeInfo(ValuesType);
    if (values_ty != .@"struct") {
        @compileError("expected tuple or struct argument, found " ++ @typeName(ValuesType));
    }

    const fields_info = values_ty.@"struct".fields;

    var current = start;

    inline for (fields_info) |field| {
        current += @field(values, field.name);
    }

    return current;
}

const PageTableLevel = enum { pml4, pdp, pd, pt };

pub inline fn alignToPage(addr: [*]const u8) [*]align(0x1000) const u8 {
    // stdlib doens't seem to have a builtin to align a pointer down to a given alignment (only up.).
    // so in the future add a more generic function to do so. (perhaps in the stdlib port?).
    return @alignCast(addr - (@intFromPtr(addr) % 0x1000));
}

const PageTable = [512]TableEntry;

pub fn mmAllocatePageTableForMapping(page: [*]align(0x1000) const u8) !*TableEntry {
    std.debug.assertAligned(page, .fromByteUnits(0x1000));

    const index = PageAccessor.fromAddrAligned(page);

    var pdp = &PageAccessor.asPointer(PageTable, .{})[index.pml4];

    if (!pdp.present) {
        pdp.setAddr(try pfm.pmmAllocatePage());
        pdp.present = true;
        pdp.writable = true;
    }

    if (pdp.huge) todo("huge pages");

    const pd = &PageAccessor.asPointer(PageTable, .{
        .pt = index.pml4,
    })[index.pdp];

    if (!pd.present) {
        pd.setAddr(try pfm.pmmAllocatePage());
        pd.present = true;
        pd.writable = true;
    }

    if (pd.huge) todo("huge pages");

    const pt = &PageAccessor.asPointer(PageTable, .{
        .pd = index.pml4,
        .pt = index.pdp,
    })[index.pd];

    if (!pt.present) {
        pt.setAddr(try pfm.pmmAllocatePage());
        pt.present = true;
        pt.writable = true;
    }

    if (pt.huge) todo("huge pages");

    const pe = &PageAccessor.asPointer(PageTable, .{
        .pdp = index.pml4,
        .pd = index.pdp,
        .pt = index.pd,
    })[index.pt];

    return pe;
}

pub inline fn todo(comptime tag: []const u8) noreturn {
    @panic(std.fmt.comptimePrint("not yet implemented: {s}", .{tag}));
}

pub fn mmWalkPageTableForMapping(page: [*]align(0x1000) const u8) !?*TableEntry {
    std.debug.assertAligned(page, .fromByteUnits(0x1000));

    const index = PageAccessor.fromAddrAligned(page);

    const pdp = &PageAccessor.asPointer(PageTable, .{})[index.pml4];

    if (!pdp.present) return null;

    if (pdp.huge) todo("huge pages");

    const pd = &PageAccessor.asPointer(PageTable, .{
        .pt = index.pml4,
    })[index.pdp];

    if (!pd.present) return null;

    if (pd.huge) todo("huge pages");

    const pt = &PageAccessor.asPointer(PageTable, .{
        .pd = index.pml4,
        .pt = index.pdp,
    })[index.pd];

    if (!pt.present) return null;

    if (pt.huge) todo("huge pages");

    const pe = &PageAccessor.asPointer(PageTable, .{
        .pdp = index.pml4,
        .pd = index.pdp,
        .pt = index.pd,
    })[index.pt];

    return pe;
}

pub fn mmGetPhysicalPage(addr: [*]align(0x1000) const u8) !usize {
    const entry = try mmWalkPageTableForMapping(addr);

    if (entry == null)
        return error.NoSuchMapping;

    return entry.?.getAddr();
}

const MapOptions = packed struct {
    writable: bool = true,
    noCache: bool = false,
    writeThrough: bool = false,
};

pub fn mapPage(physical: usize, virtual: *anyopaque, attributes: MapOptions) !void {
    _ = physical;
    _ = virtual;
    _ = attributes;
}

pub fn unmapPage(virtual: *anyopaque) !void {
    _ = virtual;

    @panic("todo");
}

pub fn init() !void {
    klog.info("Initializing kernel paging...", .{});

    // setup recursive mapping
    var pml4Mapping = &(getPML4()[510]);
    pml4Mapping.present = true;
    pml4Mapping.writable = true;
    pml4Mapping.setAddr(@intFromPtr(getPML4()));

    klog.info("Recursive Page Table mapped to {x}...", .{PageAccessor.asAddr(.{
        .pdp = 0,
        .pd = 0,
        .pt = 0,
    })});

    const exampleVirt = alignToPage(@ptrFromInt(0xFFFF_FFFA_1234_0000));
    klog.debug("==== PAGE ACCESSOR TEST ====", .{});
    klog.debug("Example Address (Virtaddr): 0x{x}", .{@intFromPtr(exampleVirt)});
    const exampleIdx = PageAccessor.fromAddrAligned(exampleVirt);
    klog.debug("Index: {any}", .{exampleIdx});
    const reconstAddr = exampleIdx.asAddr();
    klog.debug("Reconstructed Addr: 0x{x}", .{reconstAddr});
    klog.debug("Reconstructed Index: {any}", .{PageAccessor.fromAddrAligned(@ptrFromInt(reconstAddr))});
    klog.debug("==== PAGE MAPPING TEST ====", .{});

    const example: *volatile usize = @ptrFromInt(try pfm.pmmAllocatePage());

    // lower half is identity mapped!
    example.* = 0x12345;

    klog.debug("Physical Address: {x}", .{@intFromPtr(example)});
    klog.debug("Physical Read: 0x{x}", .{example.*});

    const mapping = try mmAllocatePageTableForMapping(exampleVirt);
    klog.debug("Page Table Entry (Virtaddr): 0x{x}", .{@intFromPtr(mapping)});

    mapping.huge = true;
    mapping.present = true;
    mapping.writable = true;
    mapping.setAddr(@intFromPtr(example));

    klog.debug("Virt Read: 0x{x}", .{std.mem.bytesToValue(usize, exampleVirt)});

    const vexample: *volatile usize = @ptrCast(@constCast(std.mem.bytesAsValue(usize, exampleVirt)));

    klog.debug("Writing 0xABCDF to virtual addr...", .{});
    vexample.* = 0xABCDF;

    klog.debug("Physical Read: 0x{x}", .{example.*});

    klog.debug("==== END TESTS ====", .{});

    klog.debug("mmGetPhysicalPage(example) = 0x{x}", .{try mmGetPhysicalPage(exampleVirt)});

    return todo("complete memory manager init");
}

pub const TableEntry = packed struct {
    present: bool,
    writable: bool,
    user: bool,
    write_through: bool,
    disable_cache: bool,
    accessed: bool,
    dirty: bool = false,
    pat: bool = false,
    huge: bool = false,
    avail0: u3,
    addr: u40,
    avail1: u11,
    no_execute: bool,

    pub fn asTable(self: *const @This()) *[512]TableEntry {
        return @ptrFromInt(self.getAddr());
    }

    pub fn getAddr(self: *const @This()) usize {
        return self.addr << 12;
    }

    pub fn setAddr(self: *@This(), addr: usize) void {
        self.addr = @intCast(addr >> 12);
    }
};

fn getPML4() *[512]TableEntry {
    const addr = asm volatile (
        \\mov %cr3,%[ret]
        : [ret] "=r" (-> u64),
    );
    return @ptrFromInt(addr);
}
