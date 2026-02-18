const bootboot = @import("bootboot.zig");
const std = @import("std");

var totalPhysicalPages: usize = 0;

pub export fn totalUsablePhysicalPages() usize {
    if (totalPhysicalPages > 0)
        return totalPhysicalPages
    else {
        @branchHint(.unlikely);

        for (bootboot.bootboot.mmap_entries()) |entry| {
            totalPhysicalPages += entry.getSizeIn4KiBPages();
        }

        return totalPhysicalPages;
    }
}

pub export fn getHighestPhysicalPageNumber() u32 {
    var end: usize = 0;

    for (bootboot.bootboot.mmap_entries()) |ent| {
        if (!ent.isFree()) continue;
        if (end < ent.endPtr()) end = ent.endPtr();
    }

    const pages = end / 0x1000;

    if (pages >= std.math.maxInt(u32)) {
        @panic("physical memory too larger");
    }

    return @truncate(pages);
}

pub export fn totalPhysicalPagesWithHoles() u32 {
    var end: usize = 0;

    for (bootboot.bootboot.mmap_entries()) |ent| {
        if (end < ent.endPtr()) end = ent.endPtr();
    }

    const pages = end / 0x1000;

    if (pages >= std.math.maxInt(u32)) {
        @panic("physical memory too larger");
    }

    return @truncate(pages);
}

pub inline fn memory_map() []bootboot.MMapEnt {
    return bootboot.bootboot.mmap_entries();
}
