const std = @import("std");
const hal = @import("../hal.zig");
const lapic = @import("lapic.zig");
const apic = @import("apic.zig");
const interrupts = @import("../interrupts.zig");
const tsc = @import("../arch/tsc.zig");
const kpcb = @import("../../ke/kpcb.zig");
const Scheduler = @import("../../sched/scheduler.zig");

const log = std.log.scoped(.lapic_timer);

const divisor: u32 = 0x3;
const register = @intFromEnum(lapic.LvtIndex.timer);
const divisor_reg = 0x3E;
const initiale_count_reg = 0x38;
const current_count_reg = 0x39;

pub fn isEnabled() bool {
    return lapic.readRawRegister(lapic.LvtEntry, register).masked;
}

pub fn setInitialeCount(microseconds: u32) void {
    lapic.writeRawRegister(
        u32,
        initiale_count_reg,
        (microseconds * kpcb.local.lapic_ticks_per_microsecond),
    );
}

pub fn init() !void {
    const oldIrql = hal.raise(.sync);
    defer hal.update(oldIrql);

    const localTimerIrq = try interrupts.create(.clock);

    lapic.writeRawRegister(apic.LocalApic.LvtEntry, @intFromEnum(apic.LocalApic.LvtIndex.timer), apic.LocalApic.LvtEntry{
        .masked = true,
        .vector = 0x00,
        .mode = .{ .timer = .periodic },
        .trigger_mode = .edge,
    });
    lapic.writeRawRegister(u32, divisor_reg, divisor);
    lapic.writeRawRegister(u32, initiale_count_reg, std.math.maxInt(u32));
    tsc.stall(1);
    const end = lapic.readRawRegister(u32, current_count_reg);
    kpcb.local.lapic_ticks_per_microsecond = if (end == std.math.maxInt(u32)) 1 else (std.math.maxInt(u32) - end);

    setInitialeCount(1000);

    log.debug("ticks per microsecond: {d}", .{kpcb.local.lapic_ticks_per_microsecond});

    localTimerIrq.attach(&handler, null);
    try localTimerIrq.bindAndConnectLocal(.timer);
}

fn handler(_: *interrupts.TrapFrame, _: ?*anyopaque) callconv(.c) bool {
    log.info("interrupt", .{});
    return true;
}
