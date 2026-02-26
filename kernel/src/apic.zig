//! Advanced Programmable Interrupt Controller

const std = @import("std");
const zuacpi = @import("zuacpi");
const kpcb = @import("kpcb.zig");

const LocalApic = @import("apic/lapic.zig");
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


pub var local_apics: MultiBoundedArrray(LocalApic, 255) = .{ .len = 0 };

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
                log.info("{any}", .{lapic});
                // const idx = try local_apics.append(.{
                //     .id = lapic.local_apic_id,
                //     .enabled = lapic.flags.enabled,
                //     .online_capable = lapic.flags.online_capable,
                //     .uid = lapic.processor_uid,
                // });

                // if (lapic.local_apic_id > 255) @panic("too many local apics");
                
                // if (kpcb.cpu_cores[lapic.local_apic_id]) |ctx| {
                //     ctx.lapic_index = @intCast(idx);
                // }
            },
            else => {}
        }
    }
}
