//! Stacktraces

const std = @import("std");
const symbols = @import("elf_symbols.zig");
const Writer = std.io.Writer;
pub const StackTrace = std.builtin.StackTrace;


pub fn captureAndWriteStackTrace(w: *Writer, first_addr: ?usize, fp: ?usize) !void {
    var iter = std.debug.StackIterator.init(first_addr, fp);
    try w.writeAll("format: #<index> <module> <address> <symbol>+<offset>\r\n");
    var frames: usize = 0;
    while (iter.next()) |addr| {
        try writeStackTraceLine(w, addr, frames);
        frames += 1;
    }
}

pub fn writeStackTrace(w: *Writer, stack_trace: *const StackTrace) !void {
    try w.writeAll("format: #<index> <module> <address> <symbol>+<offset>\r\n");

    const frame_count = @min(stack_trace.index, stack_trace.instruction_addresses.len);

    var frame_index: usize = 0;
    var frames_left: usize = frame_count;

    while (frames_left != 0) : ({
        frames_left -= 1;
        frame_index = (frame_index + 1) % stack_trace.instruction_addresses.len;
    }) {
        const addr = stack_trace.instruction_addresses[frame_index];
        try writeStackTraceLine(w, addr, frame_index);
    }

    if (stack_trace.index > stack_trace.instruction_addresses.len) {
        const dropped_frames = stack_trace.index - stack_trace.instruction_addresses.len;

        try w.print("({d} additional stack frames skipped...)\r\n", .{dropped_frames});
    }

}

fn writeStackTraceLine(w: *Writer, addr: usize, index: usize) !void {
    const resolved = symbols.resolve(addr) orelse symbols.Resolved{
        .name = "<unknown>",
        .offset = 0x0,
    };

    try w.print(
        "#{d} kernel 0x{x} {s}+0x{x}\r\n",
        .{
            index,
            addr,
            resolved.name,
            resolved.offset,
        },
    );
}
