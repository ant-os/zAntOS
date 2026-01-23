//! Global Descriptor Table
//!

const std = @import("std");

pub var GDT: Gdt = .{};

pub const Gdt = packed struct {
    null: SegmentDescriptor = .@"null",
    kernel_code: SegmentDescriptor = .{
        .access_byte = .{
            .executable = true,
        },
        .long_mode = true,
    },
    kernel_data: SegmentDescriptor = .{
        .access_byte = .{
            .readwrite = true,
        },       
        .long_mode = false,
    },
    user_code: SegmentDescriptor = .{
        .access_byte = .{
            .executable = true,
            .dpl = .user,
        },
        .long_mode = true,

    },
    user_data: SegmentDescriptor = .{
        .access_byte = .{
            .readwrite = true,
            .dpl = .user,
        },
        .long_mode = false,
    },
};

pub const GdtDescriptor = packed struct {
    size: u16,
    offset: u64,

    pub inline fn entries(self: GdtDescriptor) []SegmentDescriptor {
        const count = (self.size + 1) / @sizeOf(SegmentDescriptor);
        const table: [*]SegmentDescriptor = @ptrFromInt(self.offset);
        return table[0..count - 1];
    }

    pub inline fn get() GdtDescriptor {
        var gdt: GdtDescriptor = undefined;

        asm volatile (
            \\sgdt %[gdt]
            :
            : [gdt] "*p" (&gdt),
        );

        return gdt;
    }
};

pub fn init() void {
    const gdtr: GdtDescriptor = .{
        .offset = @intFromPtr(&GDT),
        .size = @sizeOf(Gdt) - 1,
    };

    asm volatile (
        \\lgdt %[p]
        :
        : [p] "*p" (&gdtr),
    );

    asm volatile (
        \\ pushq %[csel]
        \\ leaq 1f(%%rip), %%rax
        \\ pushq %%rax
        \\ .byte 0x48, 0xCB // Far return
        \\ 1:
        :
        : [csel] "i" (SegmentSelector.kernel_code.raw()),
        : .{ .rax = true }
    );

    asm volatile (
        \\ mov %[dsel], %%ds
        \\ mov %[dsel], %%fs
        \\ mov %[dsel], %%gs
        \\ mov %[dsel], %%es
        \\ mov %[dsel], %%ss
        :
        : [dsel] "rm" (SegmentSelector.kernel_data.raw()),
    );
}

pub const PrivilegeLevel = enum(u2) {
    kernel = 0,
    user = 3,
    _
};

pub const SegmentSelector = packed struct(u16) {
    pub const @"null": SegmentSelector =  @bitCast(@as(u16, 0));
    pub const kernel_code: SegmentSelector = .{
        .rpl = .kernel,
        .ti = .gdt,
        .index = 1,
    };
    pub const kernel_data: SegmentSelector = .{
        .rpl = .kernel,
        .ti = .gdt,
        .index = 2,
    };
    pub const user_code: SegmentSelector = .{
        .rpl = .user,
        .ti = .gdt,
        .index = 3,
    };
    pub const user_data: SegmentSelector = .{
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

    pub inline fn raw(self: SegmentSelector) u16 {
        return @bitCast(self);
    }

    pub fn fromDescriptor(idx: usize, entry: SegmentDescriptor) SegmentSelector {
        return .{
            .rpl = entry.access_byte.dpl,
            .ti = .gdt,
            .index = @truncate(idx),
        };
    }
};

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

pub const SegmentDescriptor = packed struct(u64) {
    pub const @"null": SegmentDescriptor = @bitCast(@as(u64, 0));

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
