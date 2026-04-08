//! Time Stamp Counter

const std = @import("std");
const kmod = @import("kmod");

const bootloader = kmod.antboot;
const irql = kmod.hal;

pub var microseconds_per_cycle: u64 = 100;

pub inline fn readRaw() u64 {
    return asm volatile (
        \\rdtsc
        \\shlq $32, %rdx
        \\orq %rdx, %rax
        : [ret] "={rax}" (-> u64),
        :
        : .{ .rdx = true });
}

pub fn read() u64 {
    return readRaw() / microseconds_per_cycle;
}

pub fn convert(microseconds: u64) u64 {
    return microseconds / microseconds_per_cycle;
}

pub fn delay(cycles: u64) void {
    const start = readRaw();
    const end = start + cycles;
    while (readRaw() < end) {}
}

/// Delays exection for atleast the given amount of microseconds.
pub fn stall(microseconds: u64) void {
    const start = read();
    const end = start + microseconds;
    while (read() < end) {
        std.atomic.spinLoopHint();
    }
}

pub fn init() !void {
    microseconds_per_cycle = bootloader.info.us_per_cycle;
}
