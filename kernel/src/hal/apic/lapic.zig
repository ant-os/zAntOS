//! Local Advanced Programmable Interrupt Controller

const std = @import("std");
const apic = @import("apic.zig");
const physmap = @import("../../mm/physmap.zig");

id: u32,
enabled: bool,
online_capable: bool,
processor_uid: u32,

pub var supports_eoi_broadcast_suppression: bool = false;

pub const TimerMode = enum(u2) {
    one_shot = 0,
    periodic = 1,
    tsc_deadline = 2,
    _,
};

pub const ErrorStatusRegister = packed struct(u32) {
    send_checksum: bool,
    recv_checksum: bool,
    send_accept: bool,
    recv_accept: bool,
    redirectable_ipi: bool,
    send_illegal_vector: bool,
    recvd_illegal_vector: bool,
    illegal_register_address: bool,
    _: u24 = 0,
};

pub const SpuriousInterrupt = packed struct(u32) {
    spurious_vector: u8,
    apic_software_enabled: bool,
    focus_processor_checking: bool,
    _reserved1: u2 = 0,
    suppress_eoi_broadcast: bool,
    _reserved2: u19 = 0,
};

pub const CommandRegister = packed struct(u64) {
    vector: u8,
    delivery: apic.DeliveryMode,
    dest_mode: apic.DestinationMode,
    pending: bool = false,
    _1: u1 = 0,
    assert: bool = true,
    trigger_mode: apic.TriggerMode,
    _2: u2 = 0,
    shorthand: enum(u2) {
        none,
        self,
        all,
        others,
    },
    _3: u36 = 0,
    dest: u8,
};

pub const LvtEntry = packed struct(u32) {
    vector: u8,
    delivery_mode: apic.DeliveryMode = .fixed,
    _1: u1 = 0,
    pending: bool = false,
    polarity: apic.Polarity = .active_high,
    remote_irr: bool = false,
    trigger_mode: apic.TriggerMode,
    masked: bool,
    mode: packed union {
        unused: u2,
        timer: TimerMode,
    },
    _2: u13 = 0,
};

pub const LvtIndex = enum(u7) {
    cmci = 0x2f,
    timer = 0x32,
    thermal_monitor = 0x33,
    perf_counter = 0x34,
    lint0 = 0x35,
    lint1 = 0x36,
    err = 0x37,
    _,
};

pub const RegisterId = enum(u7) {
    id = 0x02,
    version = 0x03,
    eoi = 0x0B,
    spurious = 0x0F,
    isr = 0x10,
    tmr = 0x18,
    irr = 0x20,
    esr = 0x28,
    icr = 0x30,
};

pub const LapicVersion = packed struct(u32) {
    version: u8,
    _1: u8 = 0,
    max_lvt_entry: u8 = 0,
    supports_eoi_broadcast_suppression: bool,
    _2: u7 = 0,
};

pub inline fn RegisterType(comptime reg: u7) type {
    return switch (reg) {
        0x02, 0x0B => u32,
        0x03 => LapicVersion,
        0x0F => SpuriousInterrupt,
        0x28 => ErrorStatusRegister,
        0x30 => CommandRegister,
        0x20...0x27, 0x10...0x17, 0x18...0x1F => u32,
        else => @compileError("UNSUPPORTED APIC REGISTER " ++ @tagName(reg)),
    };
}

const lapic_base: u64 = 0xFEE00000;

pub fn readRawRegister(comptime T: type, reg: u16) T {
    var bytes: [@sizeOf(T)]u8 = undefined;
    const slice = std.mem.bytesAsSlice(u32, &bytes);
    for (slice, 0..) |*v, i| {
        const addr = lapic_base + ((reg + i) << 4);
        v.* = physmap.read(u32, addr);
    }
    return std.mem.bytesToValue(T, &bytes);
}

pub inline fn writeRegister(comptime reg: RegisterId, value: RegisterType(@intFromEnum(reg))) void {
    return writeRawRegister(RegisterType(@intFromEnum(reg)), @intFromEnum(reg), value);
}

pub inline fn readRegister(comptime reg: RegisterId) RegisterType(@intFromEnum(reg)) {
    return readRawRegister(RegisterType(@intFromEnum(reg)), @intFromEnum(reg));
}

pub fn writeRawRegister(comptime T: type, reg: u16, value: T) void {
    const bytes = std.mem.toBytes(value);
    for (std.mem.bytesAsSlice(u32, &bytes), 0..) |v, i| {
        const addr = lapic_base + ((reg + i) << 4);
        physmap.write(u32, addr, v);
    }
}
