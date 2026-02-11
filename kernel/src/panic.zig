//! Kernel Panic

const std = @import("std");
const stacktrace = @import("debug/stacktrace.zig");
const symbols = @import("debug/elf_symbols.zig");
const arch = @import("arch.zig");
const logger = @import("logger.zig");
const status = @import("status.zig");

var zig_panic: bool = false;

pub fn __zig_panic_impl(msg: []const u8, trace: ?*const stacktrace.StackTrace, addr: ?usize) noreturn {
    if (zig_panic) arch.halt_cpu();
    zig_panic = true;

    handle_zig_panic(msg, trace, addr) catch unreachable;

    arch.halt_cpu();
}

pub fn handle_zig_panic(msg: []const u8, trace: ?*const stacktrace.StackTrace, addr: ?usize) !void {
    try logger.newline();
    try logger.writeline("==== KERNEL PANIC ====");
    try logger.newline();
    try logger.writeline("Status: <zig panic>");
    try logger.println("Message: {s}", .{msg});
    try logger.writeline("Panic Stacktrace:");
    try stacktrace.captureAndWriteStackTrace(logger.writer(), addr, null);
    if (trace != null and trace.?.index > 0) {
        try logger.writeline("Error Stacktrace:");
        try stacktrace.writeStackTrace(logger.writer(), trace.?);
    }
    try logger.newline();
    try logger.writeline("End of panic, halting cpu.");
    try logger.writer().flush();

    @breakpoint();
}

