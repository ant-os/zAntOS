//! Memory Manager

const std = @import("std");
const ktest = @import("ktest.zig");
const pfmdb = @import("mm/pfmdb.zig");
const paging = @import("mm/paging.zig");
const syspte = @import("mm/syspte.zig");

pub const Pte = @import("mm/pte.zig").Pte;
pub const VirtualAddress = paging.VirtualAddress;
pub const PhysicalAddress = paging.PhysicalAddress;
pub const PageAttributes = paging.PageAttributes;
pub const Pfi = paging.Pfi;
pub const Pfn = pfmdb.Pfn;

pub const PAGE_SHIFT = 12;
pub const PAGE_SIZE = 0x1000;
pub const PAGE_ALIGN = std.mem.Alignment.fromByteUnits(PAGE_SIZE);

pub const Order = enum(u5) {
    pub const raw_max: u5 = 18;

    page = 0,
    max = raw_max,
    invalid = std.math.maxInt(u5),
    _,

    pub inline fn newTruncated(v: u32) Order {
        return Order.new(
            if (v > raw_max) raw_max else @truncate(v),
        ).?;
    }

    pub inline fn new(v: u5) ?Order {
        if (v > raw_max) return null;
        return @enumFromInt(v);
    }

    pub inline fn raw(self: Order) ?u5 {
        if (!self.isValid()) return null;
        return @intFromEnum(self);
    }

    pub inline fn isValid(self: Order) bool {
        return @intFromEnum(self) <= raw_max;
    }

    pub inline fn assertValid(self: Order) void {
        if (ktest.enabled and !self.isValid()) @panic("invalid order");
    }

    pub inline fn totalPages(self: Order) u32 {
        return @as(u32, 1) << self.raw().?;
    }

    pub fn sub(self: Order, off: u5) ?Order {
        self.assertValid();

        return Order.new(self.raw().? - off);
    }

    pub fn add(self: Order, off: u5) ?Order {
        self.assertValid();

        return Order.new(self.raw().? + off);
    }
};

pub const PhysicalAddr = packed union {
    typed: packed struct(u64) {
        pageoff: u12 = 0,
        pfn: pfmdb.Pfn,
        unused: u20 = 0,
    },
    raw: u64,
    ptr: [*]const u8,
};

pub const LocalPool = struct {
    
    fixed_alloc: std.heap.FixedBufferAllocator,
};

pub fn map(paddr: paging.PhysicalAddress, size: usize, attrs: paging.PageAttributes) ![*]u8 {
    if ((size + paddr.split.pageoffset) >= 0x1000) return error.Unimplemented;
    const vpage = &(try syspte.reserve(1))[0];
    vpage.present = .{
        .writable = attrs.writable,
        .write_through = attrs.write_through,
        .disable_cache = attrs.no_cache,
        .no_execute = attrs.no_execute,
        .user = attrs.user,
        .addr = @intCast(paddr.split.pfn.raw()),
    };

    flushLocalTlb();

    return vpage.virtAddr().?.ptr[paddr.split.pageoffset..];
}

pub inline fn flushLocalTlb() void {
    // zig fmt: off
    asm volatile (
        \\movq %%cr3, %%rax
        \\movq %%rax, %%cr3
        ::: .{ .rax = true, .memory = true }
    );
    // zig fmt: on
}

pub fn unmap(vaddr: paging.VirtualAddress, size: usize) !void {
    if ((size + vaddr.split.pageoffset) >= 0x1000) return error.Unimplemented;

    const pte: [*]Pte = @ptrCast(vaddr.getPte());

    syspte.release(pte[0..1]);
}
