const std = @import("std");
const heap = @import("../mm/heap.zig");
const gdt = @import("../gdt.zig");
const segmentation = @import("../segmentation.zig");

const CommandLine = *std.mem.TokenIterator(u8, .any);
const commands = struct {
    pub fn hello(w: *std.io.Writer, cmdline: CommandLine) !void {
        _ = cmdline.next(); // ignore the command name
        _ = try w.print("Hello, {s}!\n\r", .{
            if (cmdline.peek() != null) cmdline.rest() else "World",
        });
    }

    pub fn panic(_: *std.io.Writer, cmdline: CommandLine) !void {
        _ = cmdline.next();

        const message = if (cmdline.peek() != null) cmdline.rest() else "user requested panic";

        @panic(message);
    }

    pub fn dumpgdt(w: *std.io.Writer, _: CommandLine) !void {
        const gdtr = gdt.current();
        try w.print("Global Descriptor Table at 0x{x} with the following entries:\r\n", .{gdtr.offset});
        for (gdtr.entries(), 0..) |entry, idx| {
            const sel = segmentation.Selector.fromDescriptor(idx, entry);
            try w.print("Segment 0x{x}: {any}\r\n", .{ sel.raw(), entry });
        }
    }

    pub fn int(_: *std.io.Writer, cmdline: CommandLine) !void {
        _ = cmdline.next();

        // const vector = try std.fmt.parseInt(u8, cmdline.next() orelse return error.ArgumentExpected, 0);

        // try w.print("Invoking interrupt vector 0x{x}.\r\n", .{vector});
        asm volatile ("int $0x80");
    }

    // unknown command hook
    // pub fn @"unknown command"(w: *std.io.Writer, cmdline: *std.mem.TokenIterator(u8, .any)) !void {
    //     try w.print("command \"{s}\" with cmdline \"{s}\".\n", .{ cmdline.next().?, cmdline.rest() });
    // }
};

const CommandHandler = fn (
    w: *std.io.Writer,
    cmdline: CommandLine,
) anyerror!void;

fn resolveCmd(comptime handlers: type, cmd: []const u8) ?*const CommandHandler {
    inline for (@typeInfo(handlers).@"struct".decls) |decl| {
        comptime if (std.mem.containsAtLeastScalar(u8, decl.name, 1, ' ')) continue;
        if (std.mem.eql(u8, decl.name, cmd)) return @field(handlers, decl.name);
    }
    return comptime if (@hasDecl(handlers, "unknown command"))
        @field(handlers, "unknown command")
    else
        null;
}

const CMDLINE_MAX_CHARS = 120;

pub fn run(out: *std.io.Writer, in: *std.io.Reader) !void {
    const cmdline_buf = try heap.allocator.alloc(u8, CMDLINE_MAX_CHARS);
    defer heap.allocator.free(cmdline_buf);

    while (true) {
        try out.writeAll("kernel> ");
        try out.flush();

        const cmdline = try in.adaptToOldInterface().readUntilDelimiter(cmdline_buf, '\n');

        var token_iter = std.mem.tokenizeAny(u8, std.mem.trim(u8, cmdline, &std.ascii.whitespace), " ");

        const cmd = token_iter.peek() orelse continue;

        if (std.mem.eql(u8, cmd, "help")) {
            inline for (@typeInfo(commands).@"struct".decls) |decl| {
                comptime if (std.mem.containsAtLeastScalar(u8, decl.name, 1, ' ')) continue;
                _ = try out.writeAll(decl.name);
                _ = try out.writeAll("\n\r");
            }

            continue;
        }

        const cmdHandler = resolveCmd(commands, cmd) orelse {
            try out.print("error: command \"{s}\" not found.\n\r", .{cmd});
            continue;
        };

        cmdHandler(out, &token_iter) catch |e| {
            if (e == error.Exit) break;
            try out.print("error({s}): {s}\n\r", .{ cmd, @errorName(e) });
        };

        try out.flush();
    }
}
