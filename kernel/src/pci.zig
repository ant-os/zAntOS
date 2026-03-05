//! PCI Bus Support

const std = @import("std");
const zuacpi = @import("zuacpi");
const io = @import("io.zig");

const pci = @This();

const log = std.log.scoped(.pci);

pub const Address = packed struct {
    function: u8 = 0,
    device: u8 = 0,
    bus: u8 = 0,
    segment: u16 = 0,
    _: u8 = 0,
};

const CONFIG_ADDRESS: u16 = 0xCF8;
const CONFIG_DATA: u16 = 0xCFC;

pub inline fn prepareLagacyIo(addr: Address, offset: usize) void {
    std.debug.assert(offset < 256);
    std.debug.assert(addr.segment == 0);

    // zig fmt: off
    const rawAddr = @as(u32, 0x80000000)
      | (@as(u32, @intCast(addr.bus)) << 16)
      | (@as(u32, @intCast(addr.device)) << 11)
      | (@as(u32, @intCast(addr.function)) << 8)
      | (@as(u32, @truncate(offset)) & 0xFC);
    // zig fmt: on

    io.writeAny(u32, CONFIG_ADDRESS, rawAddr);
}

pub fn lagacyRead(comptime T: type, addr: Address, offset: usize) T {
    @call(.always_inline, prepareLagacyIo, .{addr, offset});
    const result =  io.readAny(u32, CONFIG_DATA);
    return @truncate(result >> @truncate((offset & 2) * 8));
}

pub fn lagacyWrite(comptime T: type, addr: Address, offset: usize, value: T) void {
    @call(.always_inline, prepareLagacyIo, .{addr, offset});
    io.writeAny(u64, CONFIG_DATA, value);
}

pub fn getMmioBaseForAddress(addr: pci.Address) ?u64 {
    if (mcfg == null) return null;

    for (mcfg.?.bridges()) |bridge| {
        if (addr.segment != bridge.segment_group or addr.bus < bridge.bus_start or addr.bus > bridge.bus_end) continue;
        return bridge.base;
    }

    return null;
}


var mcfg: ?*zuacpi.mcfg.Mcfg = null;

pub fn init() !void {
    const rawMcfg = try zuacpi.uacpi.tables.find_table_by_signature(.MCFG);
    mcfg = @ptrCast(rawMcfg.location.ptr);

    for (0..256) |bus|{
        for (0..32) |dev|{
            const addr = Address{
                .bus = @truncate(bus),
                .device = @truncate(dev),
            };
            const data = .{
                .dev_id = lagacyRead(u32, addr, 0x0),
                .vendor_id = lagacyRead(u16, addr, 0x2),
                .class = lagacyRead(u16, addr, 0x8),
                .subclass = lagacyRead(u16, addr, 0x10),
                .prog_if = lagacyRead(u16, addr, 0x12),
                .header_type = lagacyRead(u32, addr, 0xC) & 0xFFFF,
            };

            if (data.vendor_id == 0xFFFF) continue;

            log.info("device at {any}: {any}", .{addr, data});
        }
    }
}
