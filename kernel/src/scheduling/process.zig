//! Process

const std = @import("std");
const arch = @import("../arch.zig");
const ob = @import("../ob/object.zig");
const heap = @import("../mm/heap.zig");

const Scheduler = @import("../scheduler.zig");
const SpinLock = @import("../sync/spin_lock.zig").SpinLock;
const Thread = @import("thread.zig");
const Process = @This();

pub const STACK_SIZE: usize = 16 * 1024;

var global_list: std.DoublyLinkedList = .{};
var global_lock: SpinLock = .{};
var last_id: std.atomic.Value(u16) = .init(0);

pub var initialSystemProcess: *Process = undefined;

pub const State = enum(u8) {
    invalid = 0,
    active,
    suspended,
    terminated,
    _,
};

header: ob.Header = .{
    .type = .process,
    .vtable = .{
        .deinit = &ob_deinit,
    },
},
id: u16,
state: State = .invalid,
node: std.DoublyLinkedList.Node = .{},
name: ?[]const u8 = null,
threads: struct {
    number: std.atomic.Value(u16),
    list: std.DoublyLinkedList,
    main: *Thread,
},
parent: ?struct {
    process: *Process,
    child_node: *std.DoublyLinkedList.Node,
},
children: struct {
    number: usize = 0,
    list: std.DoublyLinkedList = .{},
} = .{},
lock: SpinLock = .{},

pub fn createInitialSystemProcess() !*Process {
    global_lock.lock();
    defer global_lock.unlock();

    const self = try heap.allocator.create(Process);
    const nullThread = try heap.allocator.create(Thread);

    nullThread.* = .{
        .id = .{ .uint = 0 },
        .name = "NULL",
        .process = self,
        .saved_context = null,
        .state = .init(.invalid),
    };

    self.* = .{
        .id = 0,
        .name = "AntOS Kernel",
        .state = .active,
        .parent = null,
        .threads = .{
            .main = nullThread,
            .number = .init(1),
            .list = .{},
        },
    };

    self.threads.list.append(&nullThread.node);
    global_list.append(&self.node);

    initialSystemProcess = self;

    return self;
}

pub fn printIdent(self: *Process, w: *std.Io.Writer) !void {
    try w.print("Pid {d}", .{self.id});
    if (self.name != null) try w.print(" ('{s}')", .{self.name.?});
}

pub fn getState(self: *const Process) State {
    return self.state;
}

pub fn setState(self: *const Process, state: State) void{
    self.state = state;
}

pub fn dump(self: *Process, w: *std.Io.Writer, printLegend: bool) !void {
    if (printLegend) try w.writeAll("Syntax: {state}, {identifier}, Parent {parent process}, {number of threads} Threads\r\n");
    try w.print("{s}, ", .{@tagName(self.getState())});
    try self.printIdent(w);
    try w.writeAll(", Parent ");
    if (self.parent != null) try self.parent.?.process.printIdent(w) else try w.writeAll("<none>");
    try w.print(", {d} Threads\r\n", .{self.threads.number.load(.monotonic)});
    if (printLegend) try w.writeAll("\tSyntax: {idx}: {state}, {identifier}\r\n");
    var node = self.threads.list.first;
    var count: usize = 0;

    while (node != null) {
        const thread: *Thread = @fieldParentPtr("node", node.?);
        try w.print("\t{d}: {s}, ", .{ count, @tagName(thread.getState()) });
        try thread.printIdent(w);
        try w.writeAll("\r\n");

        node = node.?.next;

        count += 1;
    }

    try w.flush();
}

pub fn createThread(
    self: *Process,
    func: *const Thread.StartFunc,
    ctx: ?*anyopaque,
) !*Thread {
    self.lock.lock();
    defer self.lock.unlock();

    const stack = try Thread.initStack(heap.allocator, STACK_SIZE);

    const thread = try Thread.internalCreateNoAttach(
        self,
        stack,
        .new(func, ctx, stack),
    );
    self.threads.list.append(&thread.node);
    thread.state.store(.created, .seq_cst);

    return thread;
}

pub fn spawnThread(
    self: *Process,
    func: *const Thread.StartFunc,
    ctx: ?*anyopaque,
) !*Thread {
    const thread = try self.createThread(func, ctx);
    Scheduler.registerNewReadyThread(thread);
    return thread;
}

pub fn ob_deinit(hdr: *ob.Header) void {
    std.debug.assert(hdr.type == .process);

    const self: *Process = @fieldParentPtr("header", hdr);
    if (self.id != 0) @panic("tried to kill initial system process");
    std.debug.assert(self.threads.number.load(.monotonic) == 0);
    heap.allocator.destroy(self);
}
