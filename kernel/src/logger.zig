//! Kernel Logger
//! 

const std = @import("std");
const serial = @import("early_serial.zig");

var output: ?*std.io.Writer = null;
var com1: serial.SerialPort = .new(serial.COM1);

pub fn init() !void {
    try com1.init();
    output = &com1.writer;
}

pub inline fn writer() *std.io.Writer{
    return output orelse @panic("not writer set for logger");
}

pub inline fn print(
    comptime fmt: []const u8,
    args: anytype,
) !void {
    return writer().print(fmt, args);
}

pub inline fn newline() !void {
    return writer().writeAll("\r\n");
}

pub inline fn writeline(line: []const u8) !void {
    try writer().writeAll(line);
    return newline();
}


pub inline fn println(
    comptime fmt: []const u8,
    args: anytype,
) !void {
    return writer().print(fmt ++ "\r\n", args);
}

pub fn zig_log(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    
    writer().print(std.fmt.comptimePrint("[{s}] {s}: {s}\r\n", .{
        @tagName(message_level),
        @tagName(scope),
        format,
    }), args) catch @panic("failed to write to output");
}
