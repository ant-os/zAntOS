const std = @import("std");
const loader = @import("bootloader");
const uefi = std.os.uefi;

var totalPhysicalPages: usize = 0;
pub var info: *loader.BootInfo = undefined;

pub export fn totalUsablePhysicalPages() usize {
    var total: usize = 0;
    var iter = memoryDescriptorIter();
    while (iter.next()) |desc| {
        if (desc.type != .conventional_memory) continue;
        total += desc.number_of_pages;
    }
    return total;
}

pub export fn totalManagedPhysicalPagesWithHoles() u32 {
    if (totalPhysicalPages == 0) {
        var iter = memoryDescriptorIter();
        while (iter.next()) |desc| {
            if (desc.type == .reserved_memory_type) continue;
            const end = (desc.physical_start / 0x1000) + desc.number_of_pages;
            if (end > totalPhysicalPages) totalPhysicalPages = end;
        }
    }

    return @intCast(totalPhysicalPages);
}

pub fn memoryDescriptorIter() uefi.tables.MemoryDescriptorIterator {
    const minfo = info.memory;
    const slice: uefi.tables.MemoryMapSlice = .{
        .info = .{
            .descriptor_size = minfo.descriptor_size,
            .descriptor_version = minfo.descriptor_version,
            .key = @enumFromInt(0),
            .len = minfo.descriptor_count,
        },
        .ptr = @alignCast(@constCast(minfo.descriptors)),
    };
    return slice.iterator();
}
