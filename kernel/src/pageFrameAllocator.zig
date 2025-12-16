const std = @import("std");
const bootboot = @import("bootboot.zig");
const memory = @import("memory.zig");
const io = @import("io.zig");
const klog = std.log.scoped(.kernel);

var buffer: []u8 = undefined;
var freePages: usize = 0;
var usedPages: usize = 0;

pub fn init() !void {
    klog.info("Initalizing Page Bitmap...", .{});

    const pages = (memory.KePhysicalMemorySize() / 0x1000) + 1;
    const needed = requiredMemory(pages + 1);

    var bestBase: usize = 0;
    var bestSize: usize = std.math.maxInt(usize);

    for (bootboot.bootboot.mmap_entries()) |entry| {
        if (entry.getType() == .MMAP_FREE and entry.size >= needed and entry.size < bestSize) {
            bestBase = entry.ptr;
            bestSize = entry.size;
        }
    }

    if (bestSize == std.math.maxInt(usize))
        return error.FailedInitalizedPageBitmap;

    buffer = @as([*]u8, @ptrFromInt(bestBase))[0..needed];

    @memset(buffer, 0xFF);

    freePages = 0;
    usedPages = pages;

    for (bootboot.bootboot.mmap_entries()) |entry| {
        if (entry.getType() == .MMAP_FREE) {
            for (0..entry.getSizeIn4KiBPages()) |off| {
                try setPageState((std.mem.alignForward(usize, entry.getPtr(), 0x1000) / 0x1000) + off, true);
            }

            usedPages -= entry.getSizeIn4KiBPages();
            freePages += entry.getSizeIn4KiBPages();
        }
    }

    try reserveRegion((@intFromPtr(buffer.ptr) / 0x1000), (buffer.len / 0x1000) + 1);
}

pub inline fn getUsedMemory() usize {
    return usedPages * 0x1000;
}

pub inline fn getFreeMemory() usize {
    return freePages * 0x1000;
}

fn requiredMemory(pages: usize) usize {
    return (pages / 8) + 1;
}

pub fn isFree(index: usize) !bool {
    if (index >= buffer.len * 8)
        return error.IndexOutOfBounds;

    const byteIdx = index / 8;
    const bitIdx = index % 8;
    const bitMask = @as(u8, 1) << @intCast(bitIdx);

    return (buffer[byteIdx] & bitMask) == 0;
}

fn setPageState(index: usize, free: bool) !void {
    if (index >= buffer.len * 8)
        return error.IndexOutOfBounds;

    const byteIdx = index / 8;
    const bitIdx = index % 8;
    const bitMask = @as(u8, 1) << @intCast(bitIdx);

    buffer[byteIdx] &= ~bitMask;
    if (!free) buffer[byteIdx] |= bitMask;
}

pub inline fn totalPages() usize {
    return buffer.len * 8;
}

pub fn requestPage() !usize {
    if (freePages == 0)
        return error.OutOfMemory;

    var base: usize = 0;

    while (base < totalPages()) {
        if (try isFree(base)) {
            try setPageState(base, false);
            return base;
        }

        base += 1;
    }

    usedPages += 1;
    freePages -= 1;

    return error.OutOfMemory;
}

pub fn reserveRegion(base: usize, pages: usize) !void {
    for (base..(base + pages)) |idx| {
        try reservePage(idx);
    }
}
pub fn reservePage(index: usize) !void {
    try setPageState(index, false);

    if (try isFree(index)) {
        usedPages += 1;
        freePages -= 1;
    }
}

pub fn freePage(index: usize) !void {
    try setPageState(index, true);

    usedPages -= 1;
    freePages += 1;
}
