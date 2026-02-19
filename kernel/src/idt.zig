//! Interrupt Descriptor Table

const std = @import("std");

const segmentation = @import("segmentation.zig");
const descriptor = @import("descriptor.zig");
const arch = @import("arch.zig");
const stacktrace = @import("debug/stacktrace.zig");
const logger = @import("logger.zig");
const kpcb = @import("kpcb.zig");
const ktest = @import("ktest.zig");
const interrupts = @import("interrupts.zig");

const SavedRegisters = interrupts.SavedRegisters;
const Exception = interrupts.Exception;

export var IDT: [256]GateDescriptor = std.mem.zeroes([256]GateDescriptor);

pub inline fn nth_entry(n: u8) *GateDescriptor {
    return &IDT[n];
}



const IsrStub = *const fn () callconv(.naked) void;

comptime {
    var push: []const u8 = "\n";
    var pop: []const u8 = "\n";

    for (std.meta.fieldNames(SavedRegisters)) |reg| {
        push = "\npushq %" ++ reg ++ "\n" ++ push;
        pop = pop ++ "\npopq %" ++ reg ++ "\n";
    }

    asm (
        \\.global __isr_common
        \\.type __isr_common, @function
        \\__isr_common:
    ++ push ++
        // save the control registers
        \\mov %cr0, %rax
        \\pushq %rax
        \\mov %cr2, %rax
        \\pushq %rax
        \\mov %cr3, %rax
        \\pushq %rax
        \\mov %cr4, %rax
        \\pushq %rax
        // if from usermode we swapgs
    ++ std.fmt.comptimePrint("\ntestb $1, {d}(%rsp)\n", .{
        @offsetOf(interrupts.TrapFrame, "cs"),
    }) ++
        \\jz 1f
        \\swapgs
        // (IDEA) TODO: Preserve Debug Registers if perhaps a flag in the LocalPCB(gs:0x00) is set
        // and if we are from usermode, e.g. all interrupt and kernel code on a cpu core running in ring 0 shares
        // a single debugging state that is seperare from the usermode debug state (managed by the kernel as well).
        \\1: cld
    ++ std.fmt.comptimePrint(
        "\nmovq {d}(%rsp), %rdx\n",
        .{@offsetOf(interrupts.TrapFrame, "vector")},
    ) ++
        \\movq %rsp, %rdi
        \\callq __handle_interrupt
        \\
        \\.global __isr_return
        \\.type __isr_return, @function
        \\__isr_return:
        // if orginally from usermode we swapgs again
    ++ std.fmt.comptimePrint("\ntestb $1, {d}(%rsp)\n", .{
        @offsetOf(interrupts.TrapFrame, "cs"),
    }) ++
        \\jz 2f
        \\swapgs
        \\2: cld
        //\\movl     4(%rsp), %edx
        //\\popq     %rax
        //\\movq     $0xC0000101, %rcx
        //\\wrmsr
        //\\movl     4(%rsp), %edx
        //\\popq     %rax
        //\\movq     $0xC0000100, %rcx
        //\\wrmsr
        // skip control registers (4 times a 64bit register values).
        // this is because most of the control registers are either SHARED between user and kernel
        // or might be very inefficent to write to on every interrupt runtine exit(cr3).
        // Perhaps a flag returned by a higher level handler could be use to
        // restore the cr3/etc one but that is NOT needed at the current stage,
        // this might change later in development.
        \\add $32, %rsp 
    ++ pop ++
        \\add $16, %rsp # skip vector and error code
        \\iretq # return from interrupt
    ++ "\n");
}

pub var __stubs: [256]IsrStub = blk: {
    var stubs: [256]IsrStub = undefined;
    for (0..256) |i| {
        stubs[i] = make_isr_stub(i);
    }
    break :blk stubs;
};

fn make_isr_stub(comptime vector: u8) IsrStub {
    // zig comptime printing will fail otherwise.
    @setEvalBranchQuota(100000);
    // Exception has a _ variant so non-exception just go to that.
    const exception: Exception = @enumFromInt(vector);

    var code: []const u8 = if (exception.error_code()) "" else "pushq $0\n";
    code = code ++ std.fmt.comptimePrint("pushq ${d}\n", .{vector});
    code = code ++ "jmp __isr_common\n";

    // inline assembly needs a constant value.
    const c = code;

    return &struct {
        fn isr_stub() callconv(.naked) void {
            asm volatile (c);
        }

        comptime {
            // just to help debugging ;)
            @export(&isr_stub, .{ .name = std.fmt.comptimePrint("__isr_stub_{x:0>2}", .{vector}), .linkage = .strong });
        }
    }.isr_stub;
}

pub fn init() void {
    for (&IDT, 0..) |*e, i| {
        const stub = @intFromPtr(__stubs[i]);
        e.* = .{
            .offset_low = @truncate(stub),
            .offset_high = @truncate(stub >> 16),
            .type = .interrupt,
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

test "breakpoint" {
    const check_fp = !@import("builtin").omit_frame_pointer;

    kpcb.local.debug_interrupt_count = 0;

    const expected_fp = struct {
        pub noinline fn __test_breakpoint() usize {
            @breakpoint();
            return if (check_fp) @frameAddress() else 0;
        }
    }.__test_breakpoint();

    const last_interrupt_frame = &kpcb.current().last_interrupt_frame;

    try ktest.expectExtended(
        .{},
        @src(),
        last_interrupt_frame.is_reasonable(),
    );

    try ktest.expectExtended(
        .{ .count = kpcb.local.debug_interrupt_count },
        @src(),
        kpcb.local.debug_interrupt_count >= 1,
    );

    try ktest.expectExtended(
        .{ .exception = last_interrupt_frame.vector.exception },
        @src(),
        last_interrupt_frame.vector.exception == .breakpoint,
    );

    if(check_fp) try ktest.expectExtended(
        .{ .expected = expected_fp, .rbp = last_interrupt_frame.registers.rbp },
        @src(),
        last_interrupt_frame.registers.rbp == expected_fp,
    );

    try ktest.expectExtended(
        .{},
        @src(),
        kpcb.local.last_interrupt_handeled,
    );
}
