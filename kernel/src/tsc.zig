//! Time Stamp Counter

pub inline fn readRaw() u64 {
    return asm volatile (
        \\rdtsc
        \\shlq $32, %%rdx
        \\orq %%rdx, %%rax
        : [ret] "={rax}" (-> u64),
        :: .{ .rdx = true, .rax = true }
    );
}