//! Global Descriptor Table
//!

const std = @import("std");
const descriptor = @import("descriptor.zig");
const segmentation = @import("segmentation.zig");
const SegmentDescriptor = segmentation.Descriptor;

pub var GDT: Gdt = .{};

pub const Gdt = packed struct {
    null: SegmentDescriptor = .null,
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

pub const GdtDescriptor = descriptor.Descriptor(segmentation.Descriptor);

pub inline fn current() GdtDescriptor {
    var gdt: GdtDescriptor = undefined;

    asm volatile (
        \\sgdt %[gdt]
        :
        : [gdt] "*p" (&gdt),
    );

    return gdt;
}

var gdtr: GdtDescriptor = .{ .limit = 0xAA, .offset = 0xdeadbeef };
const gdtrp: *volatile GdtDescriptor = &gdtr;

pub noinline fn init() void {
    gdtrp.* = .{
        .limit = @sizeOf(Gdt) - 1,
        .offset = @intFromPtr(&GDT),
    };

    asm volatile (
        \\lgdt %[p]
        :
        : [p] "*p" (&gdtr.limit),
    );

    asm volatile (
        \\ pushq %[csel]
        \\ leaq 1f(%%rip), %%rax
        \\ pushq %%rax
        \\ .byte 0x48, 0xCB // Far return
        \\ 1:
        :
        : [csel] "i" (0x08),
        : .{ .rax = true });

    asm volatile (
        \\ mov %[dsel], %%ds
        \\ mov %[dsel], %%fs
        \\ mov %[dsel], %%gs
        \\ mov %[dsel], %%es
        \\ mov %[dsel], %%ss
        :
        : [dsel] "rm" (segmentation.Selector.kernel_data.raw()),
    );
}
