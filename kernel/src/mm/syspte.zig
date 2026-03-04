//! System PTE Pool

const std = @import("std");
const paging = @import("paging.zig");
const mm = @import("../mm.zig");
const Pte = @import("pte.zig").Pte;
const Pfi = paging.Pfi;

const SYSTEM_PTE_SPACE: u64 = 0xFFFF_FC00_0000_0000;

var first: ?*Pte = null;
var free_count: u32 = null;

pub fn getNext(pte: *Pte) ?*Pte {
    std.debug.assert(pte.isInList());

    return if (pte.list.next.kernel) pte.list.next.getPte() else null;
}

fn push(pte: *Pte) void {
    pte.* = .{
        .list = .{
            .next = blk: {
                if (first == null) break :blk .null;
                break :blk first.?.pfi() orelse .null;
            },
        },
    };
    first = pte;
}

fn pop() ?*Pte {
    const pte = first orelse return null;
    std.debug.assert(pte.isInList());
    first = getNext(pte);
    pte.unknown.inlist = false;
    return pte;
}

fn addPageTable(addr: u64) !void {
    if (!mm.PAGE_ALIGN.check(addr)) return error.InvalidParameter;

    const table = (try paging.allocatePageTableForMapping(addr)).parentTable;
    for (table) |*ent| {
        push(@ptrCast(ent));
    }
}

pub fn init() !void {
    try addPageTable(SYSTEM_PTE_SPACE);
}

pub fn reserve(count: u32) ![]Pte {
    if (count > 1) @panic("todo: allow for muli-page syspte allocations");

    return (pop() orelse return error.OutOfMemory)[0..1];
}

pub fn release(ptes: []Pte) void {
    for (ptes) |*pte| {
        push(pte);
    }
}
