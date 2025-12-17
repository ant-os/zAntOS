const std = @import("std");
const klog = std.log.scoped(.kernel_paging);
const bootboot = @import("bootboot.zig");

pub inline fn isCanonical(addr: usize) bool {
    klog.debug("upper: {x}", .{addr >> 48});
    return (addr >> 48) == 0x0 or (addr >> 48) == std.math.maxInt(u16);
}

const PageIndex = struct {
    directoryPointerIndex: u9,
    directoryIndex: u9,
    tableIndex: u9,
    pageIndex: u9,

    pub inline fn fromAddrAligned(addr: [*]align(0x1000) const u8) @This() {
        const raw_addr = @intFromPtr(addr) >> 12;

        // klog.debug("Creating page index for virtual addr (truncated aligned): 0x{x}", .{raw_addr});

        // TODO: use cpu's usable virtual address bits instead of hardcoding.

        if (!isCanonical(@intFromPtr(addr)))
            klog.warn("Virtual addresse 0x{x} is not canonical, upper bits will be discarded.", .{raw_addr});

        return .{ .directoryPointerIndex = @truncate(raw_addr >> 27), .directoryIndex = @truncate(raw_addr >> 18), .tableIndex = @truncate(raw_addr >> 9), .pageIndex = @truncate(raw_addr) };
    }

    pub inline fn fromAddr(addr: [*]const u8) @This() {
        return fromAddrAligned(alignToPage(addr));
    }
};

pub inline fn alignToPage(addr: [*]const u8) [*]align(0x1000) const u8 {
    // stdlib doens't seem to have a builtin to align a pointer down to a given alignment (only up.).
    // so in the future add a more generic function to do so. (perhaps in the stdlib port?).
    return @alignCast(addr - (@intFromPtr(addr) % 0x1000));
}

pub fn translatePage(addr: [*]align(0x1000) const u8) !usize {
    const index = PageIndex.fromAddrAligned(addr);

    klog.debug("index: {any}", .{index});

    const pdp = &(getPML4()[index.directoryPointerIndex]);

    if (!pdp.present)
        return error.NoSuchDP;

    klog.debug("pdp: {any}", .{pdp});

    const pd = &(pdp.asTable()[index.directoryIndex]);

    if (!pd.present)
        return error.NoSuchDir;

    const pt = &(pd.asTable()[index.tableIndex]);

    if (!pt.present)
        return error.NoSuchTable;

    if (pt.huge)
        return error.HugePage;

    const pe = &(pt.asTable()[index.pageIndex]);

    if (!pe.present)
        return error.NoSuchMapping;

    return pe.addr;
}

const MapOptions = packed struct { writable: bool = true, noCache: bool = false, writeThrough: bool = false, noSwap: bool = false, relocatable: bool = false };

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

    klog.debug("Page Index for 0xffffffffffe00000: {any}", .{translatePage(alignToPage(@ptrCast(&bootboot.bootboot)))});

    return error.NotImplemented;
}

pub const TableEntry = packed struct {
    present: bool,
    writable: bool,
    user: bool,
    write_through: bool,
    disable_cache: bool,
    accessed: bool,
    dirty: bool,
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
