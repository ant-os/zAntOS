//! Hardware Input/Output Object

const std = @import("std");
const ob = @import("../ob/object.zig");
const heap = @import("../mm/heap.zig");

const log = std.log.scoped(.hardware_io);

const HardwareIo = @This();

const PciAddress = extern struct {
    segment: u16 = 0,
    bus: u8 = 0,
    device: u8 = 0,
    function: u8 = 0,
};

pub const InternalDevice = union(enum) {
    none,
    fake: struct {
        sendback: u64,
    },
    pci: PciAddress,
    systemio: struct {
        base: u64,
        length: usize,
    },
};

header: ob.Header = .{
    .type = .hardware_io,
    .handle_count = 0,
    .vtable = .{
        .deinit = &ob_deinit,
    },
},
device: InternalDevice,

pub fn read(self: *HardwareIo, comptime T: type, offset: usize) !T {
    log.debug("read {s} for io from {any} at offset of 0x{x}", .{ @typeName(T), self.device, offset });
    switch (self.device) {
        .systemio => |io| {
            return asm volatile ("in %[port], %[result]"
                : [result] "={al},={ax},={eax}" (-> T),
                : [port] "N{dx}" (@as(u16, @intCast(io.base + offset))),
                : .{ .memory = true });
        },
        else => @panic("todo"),
    }
}

pub fn write(self: *HardwareIo, comptime T: type, offset: usize, value: T) !void {
    log.debug("write {s}@0x{x} to io of {any} at offset of 0x{x}", .{ @typeName(T), value, self.device, offset });
    switch (self.device) {
        .systemio => |io| {
            asm volatile ("out %[value], %[port]"
                :
                : [value] "{al},{ax},{eax}" (value),
                  [port] "N{dx}" (@as(u16, @intCast(io.base + offset))),
                : .{ .memory = true });
        },
        else => @panic("todo"),
    }
}

var pool: std.heap.MemoryPool(HardwareIo) = .init(heap.allocator);

pub fn fromInternal(dev: InternalDevice) !*HardwareIo {
    const self = try pool.create();
    self.* = .{
        .device = dev,
    };
    return self;
}

pub fn ob_deinit(hdr: *ob.Header) void {
    std.debug.assert(hdr.type == .hardware_io);

    const self: *HardwareIo = @fieldParentPtr("header", hdr);

    log.debug("deinit {any}", .{self});

    pool.destroy(self);
}
