const std = @import("std");
const pfmdb = @import("pfmdb.zig");
const mm = @import("../mm/mm.zig");
const pframe_alloc = @import("pframe_alloc.zig");
const arch = @import("../hal/arch/arch.zig");
const pte = @import("pte.zig");

const log = std.log.scoped(.paging);

/// Index in the PML4 used by the recursive page table, e.g. that points to the PML4 itself.
pub const RECURSIVE_ENTRY_INDEX = 510;

pub const PhysicalAddress = packed union {
    ptr: [*]u8,
    uint: u64,
    split: packed struct(u64) {
        pageoffset: u12 = 0,
        pfn: pfmdb.Pfn,
        _: u20 = 0,
    },
};

pub const Pfi = packed struct(u36) {
    pub const @"null": Pfi = @bitCast(@as(u36, 0));

    pt_index: u9,
    pd_index: u9,
    pdp_index: u9,
    pml4_index: u8,
    kernel: bool,

    pub fn getPte(self: Pfi) *pte.Pte {
        const vaddr: VirtualAddress = .{
            .pte = .{
                .pfi = self,
            },
        };

        return @ptrCast(@alignCast(vaddr.ptr));
    }

    pub fn addr(self: Pfi) VirtualAddress {
        return .{
            .split = .{
                .pt_index = self.pt_index,
                .pd_index = self.pd_index,
                .pdp_index = self.pdp_index,
                .pml4_index = self.pml4_index,
                .addressspace = if (self.kernel) .kernel else .user,
            },
        };
    }
};

pub const VirtualAddress = packed union {
    uint: u64,
    ptr: [*]u8,
    split: packed struct(u64) {
        pageoffset: u12 = 0,
        pt_index: u9,
        pd_index: u9,
        pdp_index: u9,
        pml4_index: u8,
        addressspace: enum(u17) { kernel = std.math.maxInt(u17), user = 0, _ },
    },
    pte: packed struct(u64) {
        _: u3 = 0,
        pfi: Pfi,
        addressspace: enum(u25) {
            recursive_page_tables = (std.math.maxInt(u16) << 9) | RECURSIVE_ENTRY_INDEX,
            _,
        } = .recursive_page_tables,

        pub fn ptr(self: @This()) *pte.Pte {
            if (self.addressspace != .recursive_page_tables) @panic("pte pointer outside of recursive page tables");
            const vaddr = @as(VirtualAddress, @bitCast(self));

            return @ptrCast(@alignCast(vaddr.ptr));
        }
    },

    pub fn getPfi(self: VirtualAddress) Pfi {
        return .{
            .kernel = self.split.addressspace == .kernel,
            .pml4_index = self.split.pml4_index,
            .pdp_index = self.split.pdp_index,
            .pd_index = self.split.pd_index,
            .pt_index = self.split.pt_index,
        };
    }

    pub fn getPte(self: VirtualAddress) *pte.Pte {
        const pteaddr: VirtualAddress = .{
            .pte = .{
                .pfi = self.getPfi(),
            },
        };

        return pteaddr.pte.ptr();
    }

    pub fn of(ptr: anytype) VirtualAddress {
        comptime if (@typeInfo(@TypeOf(ptr)) != .pointer) @compileError(std.fmt.comptimePrint(
            "expected a pointer found {s}",
            .{@tagName(@typeInfo(@TypeOf(ptr)))},
        ));

        return .{ .ptr = @ptrCast(@constCast(ptr)) };
    }
};

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
    parentTable: *PageTable,
};

var first_pt: bool = true;

fn __createNewPageTable() !u64 {
    if (first_pt) {
        log.debug("breakpoint for first page table allocation", .{});
        @breakpoint();
        first_pt = false;
    }

    const pfn = try pframe_alloc.lockAndAllocOrder(.page);

    // FIXME: This depends on identity mapping.
    const ptr: [*]u8 = @ptrFromInt(@as(u64, @intCast(pfn.raw())) << mm.PAGE_SHIFT);
    @memset(ptr[0..0x1000], 0);
    return @intFromPtr(ptr);
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

    const parent = PageAccessor.asPointer(PageTable, .{
        .pdp = index.pml4,
        .pd = index.pdp,
        .pt = index.pd,
    });

    const pe = &parent[index.pt];

    return .{
        .entry = pe,
        .parentTable = parent,
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
    huge: bool = false,
    pat: bool = false,
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
