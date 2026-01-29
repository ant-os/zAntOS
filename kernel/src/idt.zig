//! Interrupt Descriptor Table

const std = @import("std");

const segmentation = @import("segmentation.zig");
const descriptor = @import("descriptor.zig");

var IDT: [256]GateDescriptor = std.mem.zeroes([256]GateDescriptor);

pub inline fn nth_entry(n: u8) *GateDescriptor {
    return &IDT[n];
}

pub const Exceptions = enum(u8) {
    devide_error = 0,
    debug_exception = 1,
    nmi_interrupt = 2,
    breakpoint = 3,
    overflow = 4,
    out_of_range = 5,
    invalid_opcode = 6,
    device_not_available = 7,
    double_fault = 8,
    invalid_tss = 10,
    segment_not_preset = 11,
    stack_segment_fault = 12,
    general_protection_fault = 13,
    page_fault = 14,
    fpu_math_fault = 16,
    alignment_check = 17,
    machine_check = 18,
    simd_exception = 19,
    virtualization_exception = 20,
    control_protection_exception = 21,
};

pub fn init() void {
    const handler: u64 = @intFromPtr(&handler_test);
    for (&IDT) |*int| {
        int.* = .{
            .offset_low = @truncate(handler),
            .offset_high = @truncate(handler >> 16),
            .type = .trap,
            .dpl = 0,
            .selector = .kernel_code,
            .present = true,
        };
    }

    const desc = descriptor.Descriptor(GateDescriptor){
        .limit = (256 * @sizeOf(GateDescriptor)) - 1,
        .offset = @intFromPtr(&IDT[0]),
    };

    asm volatile (
        \\lidt %[p]
        :
        : [p] "*p" (&desc),
    );
}

export fn handler_test() callconv(.{ .x86_64_interrupt = .{} }) void {
    std.log.debug("INTERRUPT", .{});
}

pub const GateDescriptor = packed struct {
    offset_low: u16,
    selector: segmentation.Selector,
    ist: u3 = 0,
    zero: u5 = 0,
    type: enum(u4) {
        interrupt = 0xE,
        trap = 0xF,
        _,
    },
    reserved0: u1 = 0,
    dpl: u2,
    present: bool,
    offset_high: u48,
    reserved: u32 = 0,
};
