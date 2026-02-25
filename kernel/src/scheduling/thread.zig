const std = @import("std");
const arch = @import("../arch.zig");

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

// just for debugging rn this is fine as we know we will not be multi-core for now.
var last_id: u32 = 0;

id: u32,
state: State = .init,
saved_context: ?Context = null,
stack: ?[]u8 = null,
node: std.DoublyLinkedList.Node = .{},

pub fn init(
    alloc: std.mem.Allocator,
    func: *const StartFunc,
    context: ?*anyopaque,
    stacksize: usize,
) !*Thread {
    const self = try alloc.create(Thread);
    self.* = std.mem.zeroInit(Thread, .{});
    self.stack = try initStack(alloc, stacksize);

    std.log.debug("stack ptr: {any}", .{self.stack.?.ptr});

    self.saved_context = .new(func, context, self.stack.?);
    self.id = allocId: {
        const id = last_id;
        last_id += 1;
        break :allocId id;
    };

    return self;
}

pub noinline fn initStack(alloc: std.mem.Allocator, size: usize) ![]u8 {
    const stack = try alloc.alloc(u8,  size);
    @memset(stack, 0x0);
    return stack;
}
