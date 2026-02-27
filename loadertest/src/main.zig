const std = @import("std");

const LOADER_BLOCK = opaque {};
const cc = std.builtin.CallingConvention{ .x86_64_sysv = .{} };

export fn antkStartupSystem(_: *LOADER_BLOCK) callconv(cc) noreturn {
    while (true) { asm volatile ("hlt"); }
}
