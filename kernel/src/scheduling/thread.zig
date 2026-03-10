const std = @import("std");
const arch = @import("../arch.zig");
const ob = @import("../ob/object.zig");
const heap = @import("../mm/heap.zig");

pub const Context = @import("context.zig");
pub const StartFunc = fn (?*anyopaque) callconv(arch.cc) noreturn;

const Thread = @This();
const Process = @import("process.zig");

pub const State = enum(u8) {
    invalid = 0,
    created,
    ready,
    running,
    waiting,
    suspended,
    terminated,
    _,

    pub fn isSchedulable(self: State) bool {
        return switch (self) {
            .invalid => @panic("thread has invalid state"),
            .running, .ready, .waiting, .suspended => true,
            else => false,
        };
    }
};

pub const Id = packed union {
    pub const @"null": Id = .{ .uint = 0 };
    uint: u32,
    split: packed struct(u32) {
        thread: u16,
        process: u16,
    },
};

header: ob.Header = .{
    .type = .thread,
    .vtable = .{
        .deinit = &ob_deinit,
    },
},
id: Id,
process: *Process,
name: ?[]const u8 = null,
state: std.atomic.Value(State) = .init(.invalid),
saved_context: ?Context = null,
stack: ?[]u8 = null,
node: std.DoublyLinkedList.Node = .{},
queue_node: std.DoublyLinkedList.Node = .{},
quatum: u64 = 0,

pub fn swapState(self: *Thread, state: State) State {
    return self.state.swap(state, .seq_cst);
}

pub fn setState(self: *Thread, state: State) void {
    self.state.store(state, .seq_cst);
}

pub fn getState(self: *const Thread) State {
    return self.state.load(.seq_cst);
}

pub fn internalCreateNoAttach(
    parent: *Process,
    stack: []u8,
    initial_context: ?Context,
) !*Thread {
    const self = try heap.allocator.create(Thread);
    self.* = .{
        .id = .{
            .split = .{
                .process = parent.id,
                .thread = parent.threads.number.fetchAdd(1, .monotonic),
            },
        },
        .process = parent,
        .saved_context = initial_context,
        .stack = stack,
    };

    return self;
}

pub noinline fn initStack(alloc: std.mem.Allocator, size: usize) ![]u8 {
    const stack = try alloc.alignedAlloc(u8, .fromByteUnits(16), size);
    @memset(stack, 0x0);
    return stack;
}

pub fn printIdent(self: *Thread, w: *std.Io.Writer) !void {
    try w.print("Tid {d}", .{self.id.uint});
    if (self.name != null) try w.print(" ('{s}')", .{self.name.?});
}

pub fn ob_deinit(hdr: *ob.Header) void {
    std.debug.assert(hdr.type == .thread);

    const self: *Thread = @fieldParentPtr("header", hdr);

    std.debug.assert(self.getState() != .running);

    heap.allocator.free(self.stack.?);
    heap.allocator.destroy(self);
}
