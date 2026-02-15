const bootboot = @import("bootboot.zig");


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

pub inline fn memory_map() []bootboot.MMapEnt {
    return bootboot.bootboot.mmap_entries();
}