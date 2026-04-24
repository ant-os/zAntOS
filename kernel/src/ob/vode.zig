//! Virutal File System
//!

const std = @import("std");
const ob = @import("object.zig");
const Mutex = @import("../ke/sync/Mutex.zig");
const heap = @import("../mm/heap.zig");

pub const Flags = u32;

const Vode = @This();

const log = std.log.scoped(.vfs);
const assert = std.debug.assert;

pub const Modedata = union(enum) {
    container: void,
    symlink: [:0]const u8,
    object: ?*anyopaque,
};

/// Weak reference to the parent of the current node. If root node or out-of-tree, this will be null.
parent: ?*Vode = null,
name: [:0]const u8,
children: ?std.StringHashMapUnmanaged(*Vode) = .empty,
mode: Modedata = .container,

var global_lock: ?*Mutex = null;

/// `//`, it will only be null if the the VFS has not been initialized yet.
pub var root: ?*Vode = null;
var name_arena = std.heap.ArenaAllocator.init(heap.allocator);

pub var knownObjectType: ob.KnownTypeInstance = .{
    .name = "Virtual Node",
    .base_vtable = .{ .deinit = null },
};

pub fn getLocalName(self: *const Vode) ?[]const u8 {
    return self.name;
}

pub fn deinit(self: *Vode) bool {
    if (self.parent != null) @panic("tried to delete in-tree VODE");
    if (self.mode == .object and self.mode.object != null)
        @panic("tried to delete a VODE that still has an assocated object");

    if (self.children) |chs| {
        if (chs.count() != 0) @panic("tried to delete a VODE that still has children");
        chs.deinit(heap.allocator);
    }

    return true;
}

pub fn insert(
    self: *Vode,
    name_: []const u8,
    mode: Modedata,
) !*Vode {
    if (name_.len == 0 or std.mem.eql(u8, ".", name_)) return error.InvalidParameter;

    try global_lock.?.lock();
    defer global_lock.?.unlock();

    const children = if (self.children != null) &self.children.? else return error.InvalidParameter;

    const child = try ob.allocateFreestanding(
        Vode,
        knownObjectType.getPointer(),
        @sizeOf(Vode),
        name_.len + 1,
        null,
    );

    errdefer ob.unreferenceObject(Vode, child);

    const capturedName = ob.getAuxilliaryData(@ptrCast(child));

    @memcpy(capturedName.ptr, name_);

    child.* = .{
        .name = capturedName[0..(capturedName.len - 1) :0],
        .mode = mode,
        .children = .empty,
        .parent = self,
    };

    if (children.get(name_) != null) return error.AlreadyExists;

    log.debug("inserted {s} into directory", .{capturedName});

    try children.put(
        heap.allocator,
        capturedName[0..(capturedName.len - 1)],
        child,
    );
    errdefer _ = children.remove(capturedName);

    switch (mode) {
        .object => |obj| blk: {
            if (obj == null) break :blk;
            const header = ob.getHeader(@ptrCast(obj));

            if (header.vode.cmpxchgStrong(
                null,
                child,
                .seq_cst,
                .seq_cst,
            ) != null) return error.AlreadyBound;
        },
        else => {},
    }

    // the refrence that is returned.
    ob.referenceRaw(@ptrCast(child));

    return child;
}

pub fn captureName(name: []const u8) [:0]const u8 {
    return name_arena.allocator().dupeZ(u8, name) catch @panic("failed to capture fixed name");
}

pub fn init() !void {
    std.debug.assert(global_lock == null);

    global_lock = try Mutex.new();

    root = try ob.createObject(
        Vode,
        knownObjectType.getPointer(),
        null,
        true,
        null,
        null,
        null,
        null,
    );

    root.?.* = .{
        .name = captureName("/"),
        .mode = .container,
        .children = .empty,
        .parent = null,
    };
}

const antk_c = @import("../antk/antk.zig").c;

/// Lookup a child vode by relative path.
/// If `follow_symlinks` is true, it will follow symlinks until it reaches a non-symlink node or encounters an error.
/// The remaining path after the lookup is stored in `remaining_path`.
pub fn lookupRelative(
    self: *Vode,
    path: []const u8,
    flags: Flags,
    remaining_path: *[]const u8,
) !*Vode {
    if (path.len == 0 or (path.len == 1 and path[0] == '.')) return self;

    try global_lock.?.lock();
    defer global_lock.?.unlock();

    return lookupRelativeNoLock(
        self,
        path,
        flags,
        remaining_path,
    );
}

/// Lookup a child vode by relative path.
/// If `follow_symlinks` is true, it will follow symlinks until it reaches a non-symlink node or encounters an error.
/// The remaining path after the lookup is stored in `remaining_path`.
pub fn lookupRelativeNoLock(
    self: *Vode,
    path: []const u8,
    flags: Flags,
    remaining_path: *[]const u8,
) error{ InvalidPath, NotFound, InvalidParameter }!*Vode {
    if ((flags & antk_c.OB_VODE_OPEN) == 0)
        log.warn("vfs lookup without OB_VODE_OPEN flag set!", .{});

    log.debug("looking up relative path: {s}", .{path});

    if (path.len == 0) return self;
    if (path.len == 1 and path[0] == '.') return self;
    if (path[0] == '/') return error.InvalidPath;

    var segIter = std.mem.splitScalar(u8, path, '/');
    var node = self;

    ob.referenceRaw(@ptrCast(node));

    defer remaining_path.* = segIter.rest();

    var next: ?*Vode = null;

    parse: while (segIter.peek()) |segment| : ({
        if (next == null) @panic("internal error: next vode is null");
        if (segIter.peek() != null) ob.unreferenceObject(Vode, node);
        node = next.?;
        // consume segment
        _ = segIter.next();
    }) {
        log.debug("processing seg: {s}", .{segment});

        if (segment.len == 0) return error.InvalidPath;

        if (node.children != null and ((flags & antk_c.OB_VODE_NOSHADOW) == 0))
            if (node.children.?.get(segment)) |child| {
                next = child;
                log.debug("child:{any}", .{child});
                continue :parse;
            };

        log.debug("node = {any}", .{node});

        switch (node.mode) {
            .container => return error.NotFound,
            .object => return node,
            .symlink => |dest| if ((flags & antk_c.OB_VODE_NOFOLLOW) == 0) return node else {
                log.debug("following symlink to '{s}'", .{dest});
                next = try lookupAbsoluteNoLock(
                    dest.ptr[0..dest.len],
                    antk_c.OB_VODE_OPEN | flags,
                    remaining_path,
                );
                continue :parse;
            },
        }

        unreachable;
    }

    return node;
}

pub fn lookupAbsolute(
    path: []const u8,
    flags: Vode.Flags,
    remaining_path: *[]const u8,
) !*Vode {
    try global_lock.?.lock();
    defer global_lock.?.unlock();

    return lookupAbsoluteNoLock(
        path,
        flags,
        remaining_path,
    );
}

pub fn lookupAbsoluteNoLock(
    path_: []const u8,
    flags: Vode.Flags,
    remaining_path: *[]const u8,
) !*Vode {
    if ((flags & antk_c.OB_VODE_OPEN) == 0)
        log.warn("vfs lookup without OB_VODE_OPEN flag set!", .{});

    log.debug("looking up absolute path: {s}", .{path_});

    var path: []const u8 = path_;
    const dir = blk: {
        if (std.mem.startsWith(u8, path, "//")) {
            path = path_[2..];
            break :blk Vode.root.?;
        }
        if (path_.len == 0 or path_[0] != '/') return error.InvalidPath;
        path = path_[1..];
        break :blk try Vode.root.?.lookupRelativeNoLock(
            "??/RootFs",
            antk_c.OB_VODE_OPEN,
            remaining_path,
        );
    };

    const node = try dir.lookupRelativeNoLock(
        path,
        antk_c.OB_VODE_OPEN | flags,
        remaining_path,
    );

    // TODO: check access right for vodes.
    ob.referenceRaw(@ptrCast(node));
    return node;
}
