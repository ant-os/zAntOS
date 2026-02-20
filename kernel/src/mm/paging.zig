const std = @import("std");
const pfmdb = @import("pfmdb.zig");
const mm = @import("../mm.zig");
const pframe_alloc = @import("pframe_alloc.zig");
const arch = @import("../arch.zig");

const log = std.log.scoped(.paging);

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

    pub inline fn fromAddrAligned(addr: u64) @This() {
        const raw_addr = addr >> 12;

        if (!arch.isCanonical(addr))
            log.warn("Virtual addresse 0x{x} is not canonical, upper bits will be discarded.", .{raw_addr});

        return .{
            .pml4 = @truncate(raw_addr >> 27),
            .pdp = @truncate(raw_addr >> 18),
            .pd = @truncate(raw_addr >> 9),
            .pt = @truncate(raw_addr),
        };
    }

    pub inline fn fromAddr(addr: u64) @This() {
        return fromAddrAligned(mm.PAGE_ALIGN.backward(addr));
    }
};

const PageTableLevel = enum { pml4, pdp, pd, pt };
const PageTable = [512]TableEntry;
const MappingEntry = struct {
    entry: *TableEntry,
    parentEntry: *TableEntry,
};

var first_pt: bool = true;

fn __createNewPageTable() !u64 {
    if (first_pt) {
        log.debug("breakpoint for first page table allocation", .{});
        @breakpoint();
        first_pt = false;
    }

    const pfn = try pframe_alloc.lockAndAllocOrder(.page);
    return @as(u64, @intCast(pfn.raw())) << mm.PAGE_SHIFT;
}

pub fn allocatePageTableForMapping(page: u64) !MappingEntry {
    const index = PageAccessor.fromAddrAligned(page);

    var pdp = &PageAccessor.asPointer(PageTable, .{})[index.pml4];

    if (!pdp.present) {
        pdp.setAddr(try __createNewPageTable());
        pdp.present = true;
        pdp.writable = true;
    }

    if (pdp.huge) todo("huge pages");

    const pd = &PageAccessor.asPointer(PageTable, .{
        .pt = index.pml4,
    })[index.pdp];

    if (!pd.present) {
        pd.setAddr(try __createNewPageTable());
        pd.present = true;
        pd.writable = true;
    }

    if (pd.huge) todo("huge pages");

    const pt = &PageAccessor.asPointer(PageTable, .{
        .pd = index.pml4,
        .pt = index.pdp,
    })[index.pd];

    if (!pt.present) {
        pt.setAddr(try __createNewPageTable());
        pt.present = true;
        pt.writable = true;
    }

    if (pt.huge) todo("huge pages");

    const pe = &PageAccessor.asPointer(PageTable, .{
        .pdp = index.pml4,
        .pd = index.pdp,
        .pt = index.pd,
    })[index.pt];

    return .{
        .entry = pe,
        .parentEntry = pt,
    };
}

inline fn todo(comptime tag: []const u8) noreturn {
    @panic(std.fmt.comptimePrint("not yet implemented: {s}", .{tag}));
}

pub fn walkPageTableForMapping(addr: u64) !?*TableEntry {
    const index = PageAccessor.fromAddrAligned(addr);

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

pub fn translateAddr(virtualAddr: u64) !u64 {
    const page = mm.PAGE_ALIGN.backward(virtualAddr);
    const offset: u12 = @truncate(virtualAddr);

    return (try getPhysicalPage(page)) + offset; 
}

pub fn getPhysicalPage(virtualAddr: u64) !usize {
    if (!mm.PAGE_ALIGN.check(virtualAddr))
        return error.MisalignedVirtualPage;

    const entry = (try walkPageTableForMapping(virtualAddr)) orelse return error.NotMapped;

    if (!entry.present)
        return error.NotMapped;

    return entry.getAddr();
}

pub const PageAttributes = packed struct(u8) {
    writable: bool = true,
    no_cache: bool = false,
    write_through: bool = false,
    user: bool = false,
    no_execute: bool = false,
    reserved: u3 = 0,
};

pub inline fn flushPage(virtualAddr: u64) !void {
    if (!mm.PAGE_ALIGN.check(virtualAddr)) {
        @branchHint(.unlikely); // mostly called interally after alignment was already checked.
        return error.InvalidParamter;
    }

    asm volatile (
        \\invlpg (%[page])
        :
        : [page] "r" (virtualAddr),
        : .{
          .memory = true,
        });
}

inline fn __getAndCheckPTEntry(virtual: u64) !*TableEntry {
    if (!mm.PAGE_ALIGN.check(virtual))
        return error.MisalignedVirtualPage;

    const entry = (try walkPageTableForMapping(virtual)) orelse return error.NotMapped;

    if (!entry.present)
        return error.NotMapped;

    return entry;
}

pub fn getPageAttributes(virtualAddr: u64) !PageAttributes {
    const entry = try __getAndCheckPTEntry(virtualAddr);

    return .{
        .writable = entry.writable,
        .no_cache = entry.disable_cache,
        .write_through = entry.write_through,
        .user = entry.user,
        .no_execute = entry.no_execute,
    };
}

pub fn setPageAttributes(virtualAddr: u64, attrs: PageAttributes) !void {
    var entry = try __getAndCheckPTEntry(virtualAddr);

    entry.writable = attrs.writable;
    entry.disable_cache = attrs.no_cache;
    entry.write_through = attrs.write_through;
    entry.user = attrs.user;
    entry.no_execute = attrs.no_execute;

    try flushPage(virtualAddr);
}

pub fn mapPage(physical: usize, virtual: u64, attributes: PageAttributes) !void {
    if (!mm.PAGE_ALIGN.check(virtual))
        return error.MisalignedVirtualPage;
    if (!mm.PAGE_ALIGN.check(physical))
        return error.MisalignedPhysicalPage;

    const mapping = try allocatePageTableForMapping(virtual);
    var entry = mapping.entry;

    entry.setAddr(physical);
    entry.present = true;
    entry.writable = attributes.writable;
    entry.disable_cache = attributes.no_cache;
    entry.write_through = attributes.write_through;
    entry.user = attributes.user;
    entry.no_execute = attributes.no_execute;

    try flushPage(virtual);
}

pub fn unmapPage(virtual: u64) !void {
    if (!mm.PAGE_ALIGN.check(virtual))
        return error.MisalignedVirtualPage;

    var entry = (try walkPageTableForMapping(virtual)) orelse return error.NotMapped;

    if (!entry.present)
        return error.NotMapped;

    entry.setAddr(0x0000);
    entry.present = false;
    entry.writable = false; // perhaps not needed?

    // NOTE: later add page table physical frame cleanup if needed.

    try flushPage(virtual);
}

pub fn mapRegion(
    physicalAddr: usize,
    virtualAddr: u64,
    pages: usize,
    attributes: PageAttributes,
) !void {
    // this is very simple, missing some optimizations(perhaps?) and other features, but will work for now.

    for (0..pages) |page_off| {
        try mapPage(
            physicalAddr + (page_off * 0x1000),
            virtualAddr + (page_off * 0x1000),
            attributes,
        );
    }
}

pub fn unmapRegion(
    virtualAddr: u64,
    pages: usize,
) !void {
    // same as mmMapPagedRegion but unmapping instead of mapping.

    for (0..pages) |page_off| {
        try unmapPage(
            virtualAddr + (page_off * 0x1000),
        );
    }
}

pub fn init() !void {
    log.info("Initializing kernel paging...", .{});

    // setup recursive mapping
    var pml4Mapping = &(getPML4()[510]);
    pml4Mapping.present = true;
    pml4Mapping.writable = true;
    pml4Mapping.setAddr(@intFromPtr(getPML4()));

    log.info("Recursive Page Table mapped to {x}...", .{PageAccessor.asAddr(.{
        .pdp = 0,
        .pd = 0,
        .pt = 0,
    })});
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

    pub fn getAddr(self: *const @This()) u64 {
        return self.addr << 12;
    }

    pub fn setAddr(self: *@This(), addr: u64) void {
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
