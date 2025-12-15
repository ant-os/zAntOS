const bootboot = @import("bootboot.zig");

var totalPhysicalMem: usize = 0;

pub export fn KePhysicalMemorySize() usize {
    if (totalPhysicalMem > 0)
        return totalPhysicalMem
    else {
        @branchHint(.unlikely);

        for (bootboot.bootboot.mmap_entries()) |entry| {
            totalPhysicalMem += entry.getSizeInBytes();
        }

        return totalPhysicalMem;
    }
}
