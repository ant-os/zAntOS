const std = @import("std");

pub const PrivilegeLevel = enum(u2) { kernel = 0, user = 3, _ };

pub const AccessByte = packed struct(u8) {
    pub const @"null": AccessByte = @bitCast(@as(u8, 0));

    accessed: bool = false,
    readwrite: bool = false,
    growsdown: bool = false,
    executable: bool = false,
    nonsystem_seg: bool = true,
    dpl: PrivilegeLevel = .kernel,
    present: bool = true,
};

pub const Descriptor = packed struct(u64) {
    pub const @"null": Descriptor = @bitCast(@as(u64, 0));

    // TODO: TSS Support.
    limit0: u16 = std.math.maxInt(u16),
    base0: u24 = 0x0,
    access_byte: AccessByte,
    limit1: u4 = std.math.maxInt(u4),
    reserved: u1 = 0,
    long_mode: bool,
    size32: bool = false,
    page_granularity: bool = true,
    base1: u8 = 0x0,
};
pub const Selector = packed struct(u16) {
    pub const @"null": Selector = @bitCast(@as(u16, 0));
    pub const kernel_code: Selector = .{
        .rpl = .kernel,
        .ti = .gdt,
        .index = 1,
    };
    pub const kernel_data: Selector = .{
        .rpl = .kernel,
        .ti = .gdt,
        .index = 2,
    };
    pub const user_code: Selector = .{
        .rpl = .user,
        .ti = .gdt,
        .index = 3,
    };
    pub const user_data: Selector = .{
        .rpl = .user,
        .ti = .gdt,
        .index = 4,
    };

    rpl: PrivilegeLevel,
    ti: enum(u1) {
        gdt = 0,
        ldt = 1,
    },
    index: u13,

    pub inline fn raw(self: Selector) u16 {
        return @bitCast(self);
    }

    pub fn fromDescriptor(idx: usize, entry: Descriptor) Selector {
        return .{
            .rpl = entry.access_byte.dpl,
            .ti = .gdt,
            .index = @truncate(idx),
        };
    }
};
