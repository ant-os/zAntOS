const std = @import("std");
const bootboot = @import("bootboot.zig");

pub const MAX_SUPPORTED_CORES = 8;

pub fn halt_cpu() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}

pub inline fn isCanonical(addr: usize) bool {
    return (addr >> 48) == 0x0 or (addr >> 48) == std.math.maxInt(u16);
}

pub const Msr = enum(u32) {
    fs_base = 0xC000_0100,
    gs_base = 0xC000_0101,
    kernel_gs_base = 0xC000_0102,

    pub fn read(self: Msr) u64 {
        var low: u64 = undefined;
        var high: u64 = undefined;

        asm volatile (
            \\rdmsr
            : [low] "={rax}" (low),
              [high] "={rdx}" (high)
            : [msr] "{rcx}" (@intFromEnum(self)),
            
        );

        return (high << 32) | low; 
    }

    pub fn write(self: Msr, value: u64) void{
        asm volatile (
            \\wrmsr
            :
            : [low] "{rax}" (value),
              [high] "{rdx}" (value >> 32),
              [msr] "{rcx}" (@intFromEnum(self))
        );
    }
};


pub fn numcores() usize {
    return bootboot.info.numcores;
}

pub fn bspid() u16 {
    return bootboot.info.bspid;
}

pub fn current_cpu() u16 {
    return bootboot.info.bspid;
}
