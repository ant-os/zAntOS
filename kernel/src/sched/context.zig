//! Task Context

const std = @import("std");
const interrupts = @import("../hal/interrupts.zig");
const TrapFrame = interrupts.TrapFrame;

const Context = @This();

// TODO: Segment Selectors

pub const Registers = extern struct {
    r15: u64 = 0,
    r14: u64 = 0,
    r13: u64 = 0,
    r12: u64 = 0,
    r11: u64 = 0,
    r10: u64 = 0,
    r9: u64 = 0,
    r8: u64 = 0,
    rdi: u64 = 0,
    rsi: u64 = 0,
    rbp: u64 = 0,
    rsp: u64,
    rdx: u64 = 0,
    rcx: u64 = 0,
    rbx: u64 = 0,
    rax: u64 = 0,
    rip: u64,
};

registers: Registers,


pub fn new(
    func: *const fn (?*anyopaque) callconv(.{ .x86_64_sysv = .{} }) noreturn,
    context: ?*anyopaque,
    stack: []u8,
) Context {
    return .{
        .registers = .{
            .rdi = @intFromPtr(context),
            .rsp = (@intFromPtr(stack.ptr) + (stack.len - 1)),
            .rip = @intFromPtr(func),
        },
    };
}

pub fn applyToFrame(self: *Context, frame: *TrapFrame) void {
    frame.rip = self.registers.rip;
    frame.rsp = self.registers.rsp;

    inline for (@typeInfo(interrupts.SavedRegisters).@"struct".fields) |reg| {
        @field(frame.registers, reg.name) = @field(
            self.registers,
            reg.name,
        );
    }
}

pub fn fromFrame(frame: *TrapFrame) Context {
    var self = Context{
        .registers = .{
            .rip = frame.rip,
            .rsp = frame.rsp,
        }
    };

    inline for (@typeInfo(interrupts.SavedRegisters).@"struct".fields) |reg| {
        @field(self.registers, reg.name) = @field(
            frame.registers,
            reg.name,
        );
    }


    return self;
}