const std = @import("std");
const arch = @import("../arch.zig");
const ob = @import("../ob/object.zig");
const heap = @import("../mm/heap.zig");

pub const Context = @import("context.zig");
pub const StartFunc = fn (?*anyopaque) callconv(arch.cc) noreturn;

const Thread = @This();

pub const State = enum(u8) {
    init = 0,
    ready,
    running,
    waiting,
    suspended,
    terminated,
    _,
};

pub const Id = packed union {
    uint: u32,
    split: packed struct(u32) {
        process: u16,
        thread: u16,
    },
};

// just for debugging rn this is fine as we know we will not be multi-core for now.
var last_id: u16 = 0;

header: ob.Header,
id: Id,
state: State = .init,
saved_context: ?Context = null,
stack: ?[]u8 = null,
node: std.DoublyLinkedList.Node = .{},

pub fn init(
    func: *const StartFunc,
    context: ?*anyopaque,
    stacksize: usize,
) !*Thread {
    const self = try heap.allocator.create(Thread);
    const stack = try initStack(heap.allocator, stacksize);
    self.* = .{
        .header = .{
            .type = .thread,
            .vtable = .{
                .deinit = &ob_deinit,
            },
        },
        .stack = stack,
        .saved_context = .new(func, context, stack),
        .id = allocId: {
            const id = last_id;
            last_id += 1;
            break :allocId .{
                .split = .{
                    .process = 0,
                    .thread = id,
                },
            };
        },
        .node = .{},
        .state = .init,
    };

    return self;
}

pub noinline fn initStack(alloc: std.mem.Allocator, size: usize) ![]u8 {
    const stack = try alloc.alloc(u8, size);
    @memset(stack, 0x0);
    return stack;
}

pub fn ob_deinit(hdr: *ob.Header) void {
    std.debug.assert(hdr.type == .thread);

    const self: *Thread = @fieldParentPtr("header", hdr);

    std.debug.assert(self.state != .running);

    heap.allocator.free(self.stack.?);
    heap.allocator.destroy(self);
}
