//! Interrupt Descriptor Table

const std = @import("std");

const segmentation = @import("segmentation.zig");
const descriptor = @import("descriptor.zig");

export var IDT: [256]GateDescriptor = std.mem.zeroes([256]GateDescriptor);

pub inline fn nth_entry(n: u8) *GateDescriptor {
    return &IDT[n];
}

const InterruptStackFrame = extern struct {
    ip: usize,
    cs: usize,
    flags: usize,
    sp: usize,
    ss: usize,
};

pub const Exception = enum(u8) {
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
    segment_not_present = 11,
    stack_segment_fault = 12,
    general_protection_fault = 13,
    page_fault = 14,
    fpu_math_fault = 16,
    alignment_check = 17,
    machine_check = 18,
    simd_exception = 19,
    virtualization_exception = 20,
    control_protection_exception = 21,
    _,

    pub fn error_code(self: Exception) bool {
        return switch (self) {
            .double_fault,
            .invalid_tss,
            .segment_not_present,
            .general_protection_fault,
            .page_fault,
            .control_protection_exception,
            => true,
            else => false,
        };
    }
};

pub const SavedRegisters = extern struct {
    r15: u64,
    r14: u64,
    r13: u64,
    r12: u64,
    r11: u64,
    r10: u64,
    r9: u64,
    r8: u64,
    rdi: u64,
    rsi: u64,
    rbp: u64,
    rdx: u64,
    rcx: u64,
    rbx: u64,
    rax: u64,
};

const InterruptVector = u8;

pub fn StackFrame(ErrorCode: type) type {
    if (@sizeOf(ErrorCode) > 8) @compileError(std.fmt.comptimePrint(
        "interrupt error code must be at most 8 bytes but is {d} bytes",
        .{@sizeOf(ErrorCode)},
    ));

    return extern struct {
        gs_base: usize,
        fs_base: usize,
        cr4: u64,
        cr3: u64,
        cr2: u64,
        cr0: u64,
        registers: SavedRegisters align(8),
        vector: InterruptVector align(8),
        error_code: ErrorCode align(8),
        rip: usize,
        cs: segmentation.Selector align(8),
        eflags: u64, // TODO: Typed EFLAGS.
        rsp: usize,
        ss: segmentation.Selector align(8),
    };
}

const IsrStub = *const fn () callconv(.naked) void;
const InterruptHandler = *const fn (*StackFrame(u64)) callconv(.{ .x86_64_sysv = .{} }) void;

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
        \\mov  $0xC0000100, %rcx
        \\rdmsr
        \\pushq %rax # push the first part
        \\movl %edx, 4(%rsp) # push the second part
        \\mov $0xC0000101, %rax
        \\rdmsr
        \\pushq %rax # push the first part
        \\movl %edx, 4(%rsp) # push the second part
        // if from usermode we swapgs
    ++ std.fmt.comptimePrint("\ntestb $1, {d}(%rsp)\n", .{
        @offsetOf(StackFrame(u64), "cs"),
    }) ++
        \\jz 1f
        \\swapgs
        // (IDEA) TODO: Preserve Debug Registers if perhaps a flag in the LocalPCB(gs:0x00) is set
        // and if we are from usermode, e.g. all interrupt and kernel code on a cpu core running in ring 0 shares
        // a single debugging state that is seperare from the usermode debug state (managed by the kernel as well).
        \\1: cld
    ++ std.fmt.comptimePrint(
        "\nmovq {d}(%rsp), %rdx\n",
        .{@offsetOf(StackFrame(u64), "vector")},
    ) ++
        \\movq %rsp, %rdi
        \\callq *__isrs(, %rdx, 8)
        \\
        \\.global __isr_return
        \\.type __isr_return, @function
        \\__isr_return:
        // if orginally from usermode we swapgs again
    ++ std.fmt.comptimePrint("\ntestb $1, {d}(%rsp)\n", .{
        @offsetOf(StackFrame(u64), "cs"),
    }) ++
        \\jz 2f
        \\swapgs
        \\2: cld
        \\movl     4(%rsp), %edx
        \\popq     %rax
        \\movq     $0xC0000101, %rcx
        \\wrmsr
        \\movl     4(%rsp), %edx
        \\popq     %rax
        \\movq     $0xC0000100, %rcx
        \\wrmsr
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

pub export var __isrs: [256]InterruptHandler = undefined;
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
        // std.log.debug("IDT ENTRY: {any}", .{e});
    }

    @memset(&__isrs, @ptrCast(&unhandled_interrupt));

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

pub fn set_handler(vector: u8, handler: anytype) void {
    __isrs[vector] = @ptrCast(handler);
}

pub fn unhandled_interrupt(frame: *StackFrame(u64)) callconv(.{ .x86_64_sysv = .{} }) void {
    std.log.debug("INTERRUPT {any}", .{frame});

    var iter = std.debug.StackIterator.init(null, frame.registers.rbp);

    while (iter.next()) |fr| {
        std.log.debug("STACK FRAME: 0x{x}", .{fr});
    }
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
