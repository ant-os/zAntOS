//! Advanced Programmable Interrupt Controller

const std = @import("std");
const zuacpi = @import("zuacpi");
const kpcb = @import("kpcb.zig");
const irql = @import("interrupts/irql.zig");

const Msr = @import("arch.zig").Msr;
pub const LocalApic = @import("apic/lapic.zig");
const MultiBoundedArrray = @import("utils/multi_bounded_array.zig").MultiBoundedArray;
const log = std.log.scoped(.apic);

pub const DeliveryMode = enum(u3) {
    fixed = 0,
    lowest = 1,
    smi = 2,
    nmi = 4,
    init = 5,
    startup = 6,
    exint = 7,
};

pub const TriggerMode = enum(u1) {
    edge = 0,
    level = 1,
};

pub const DestinationMode = enum(u1) {
    physical = 0,
    logical = 1,
};

pub const Polarity = enum(u1) {
    active_high = 0,
    active_low = 1,
};

pub fn init() !void {
    const madt: *align(1) const zuacpi.madt.Madt = @ptrFromInt(
        (try zuacpi.uacpi.tables.find_table_by_signature(.APIC)).location.virt_addr,
    );

    var madt_iter = madt.iterator();

    while (madt_iter.next()) |n| {
        log.debug("madt entry: {any}", .{n});

        switch (n) {
            .local_apic => |v| {
                const lapic = @as(*align(1) const zuacpi.madt.MadtEntryPayload(.local_apic), v);

                if (kpcb.cpu_cores[lapic.local_apic_id]) |ctx| ctx.lapic = .{
                    .id = lapic.local_apic_id,
                    .enabled = lapic.flags.enabled,
                    .online_capable = lapic.flags.online_capable,
                    .processor_uid = lapic.processor_uid,
                };
            },
            else => {},
        }
    }

        log.info("{any}", .{kpcb.current().lapic});

    const lapic = kpcb.current().lapic;

    if (!lapic.enabled) @panic("local apic not enabled");

    Msr.write(.apic_base, 0xFEE00000 & 0x800);

    const version = LocalApic.readRegister(.version);

    log.debug("lapic.supports_eoi_broadcast_suppression = {any}", .{version.supports_eoi_broadcast_suppression});

    var spuriousReg = LocalApic.readRegister(.spurious);

    spuriousReg.apic_software_enabled = true;
    spuriousReg.spurious_vector = 0xFF;
    spuriousReg.suppress_eoi_broadcast = spuriousReg.suppress_eoi_broadcast;

    LocalApic.writeRegister(.spurious, spuriousReg);
}

pub inline fn eoi() void {
    LocalApic.writeRegister(.eoi, 0);
}

pub fn send_ipi(ipi: LocalApic.CommandRegister) void {
    std.debug.assert(!LocalApic.readRegister(.icr).pending);
    std.debug.assert(ipi.pending == false);
    const oldIrql = irql.raise(.deferred);
    LocalApic.writeRegister(.icr, ipi);
    irql.update(oldIrql);
    while (LocalApic.readRegister(.icr).pending) {
        std.atomic.spinLoopHint();
    }
}