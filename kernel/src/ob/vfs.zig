//! Virutal File System
//!

const std = @import("std");
const ob = @import("object.zig");
const Mutex = @import("../ke/sync/Mutex.zig");
const heap = @import("../mm/heap.zig");

const log = std.log.scoped(.vfs);

pub const Node = struct {
    parent: ?*Node = null,
    payload: union(enum) {
        normal: std.StringArrayHashMapUnmanaged(*Node),
        symlink: []const u8,
        hardlink: *Node,
        exit: void,
    } = .{ .normal = .{} },
    object: ?*anyopaque = null,
};

var global_lock: ?*Mutex = null;
var root: Node = .{};

pub fn init() !void {
    global_lock = try Mutex.new();
    try global_lock.?.lock();
    defer global_lock.?.unlock();

    const vfsroot = try heap.allocator.create(Node);
    vfsroot.* = .{
        .parent = &root,
    };

    try root.payload.normal.put(heap.allocator, "", vfsroot);
}

pub fn resolve(path: []const u8) !?*anyopaque {
    try global_lock.?.lock();
    defer global_lock.?.unlock();

    return (try resolveNodeNoLock(path, false)).object;
}

pub fn attach(path: []const u8, obj: *anyopaque) !void {
    try global_lock.?.lock();
    defer global_lock.?.unlock();

    log.debug("attaching object at '{s}' with header: {any}", .{ path, obj });

    const node = try resolveNodeNoLock(path, true);
    node.object = obj;
}

pub fn resolveNodeNoLock(path: []const u8, createMissing: bool) !*Node {
    if (!std.mem.startsWith(u8, path, "/")) return error.RelativePath;

    log.debug("resolving node for path '{s}', createMissing={any}", .{ path, createMissing });

    var segIter = std.mem.splitScalar(u8, path[1..path.len], '/');
    var node = &root;
    var allowEmpty = true;
    res: while (segIter.next()) |segment| {
        if (!allowEmpty and segment.len == 0) return error.InvalidPath;
        allowEmpty = false;

        log.debug("path segment: '{s}'", .{segment});

        std.debug.assert(node.payload == .normal);

        node = node.payload.normal.get(segment) orelse blk: {
            if (!createMissing) {
                log.debug("ERROR: segment not found and createMissing is false", .{});
                return error.NotFound;
            }
            log.debug("creating missing segmented...", .{});
            const new = try heap.allocator.create(Node);
            new.* = .{
                .parent = node,
                .payload = .{ .normal = .{} },
            };
            const key = try heap.allocator.dupe(u8, segment);
            try node.payload.normal.putNoClobber(heap.allocator, key, new);
            break :blk new;
        };

        log.debug("node has {s} payload", .{@tagName(node.payload)});

        node = switch (node.payload) {
            .normal => continue :res,
            .exit => break :res,
            .hardlink => |dest| dest,
            .symlink => |dest| try resolveNodeNoLock(dest, false),
        };
    }

    return node;
}
