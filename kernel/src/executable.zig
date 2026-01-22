//! Executable Information (Driver or Kernel Image).
//! Managed wrapper for a unmanaged Executable Info Struct, NOT ABI-Safe.
//! See `Unmanaged` for details on externally usable fields.

const std = @import("std");

pub const Managed = @This();

const ResourceDescriptor = @import("resource.zig").ResourceDescriptor;

const KERNEL_START: u64 = @import("bootboot.zig").BOOTBOOT_CORE;
const KERNEL_SIZE: u64 = std.math.maxInt(u64) - KERNEL_START;

node: std.DoublyLinkedList.Node,
resources: std.DoublyLinkedList,
unmanaged: Unmanaged,

var kernel_exe: Managed = .{
    .node = .{},
    .resources = .{},
    .unmanaged = .{
        .name = "<kernel>",
        .base = @ptrFromInt(KERNEL_START),
        .vm_size = KERNEL_SIZE,
        .num_resources = 0,
        .handle = null,
        .flags = .{ .kernel = true },
    },
};

var loaded_executables: std.DoublyLinkedList = .{
    .first = &kernel_exe.node,
    .last = &kernel_exe.node,
};
var loaded_executable_count: u64 = 1;

/// Executable Information (ABI-Safe, Unmanaged).
pub const Unmanaged = extern struct {
    /// name of the executable
    name: [*:0]const u8,
    /// base of the region of memory reserved for this executable
    base: [*]const u8,
    /// total size of the executables virtual memory region
    vm_size: usize,
    /// executable flags
    flags: packed struct(u8) {
        /// is it the os kernel.
        kernel: bool,
        /// reseved for future use.
        reserved: u7 = 0,
    },

    /// number of resources owned by this executable.
    num_resources: u64,

    /// handle to a resource associated with this executable.
    handle: ?*ResourceDescriptor,

    /// Get the wrapping Managed Executable Information.
    /// SAFETY: self MUST be a managed executable's unmanaged information obtained via `asUnmanaged`.
    pub inline fn asManaged(self: *const Unmanaged) *const Managed {
        return @fieldParentPtr("unmanaged", self);
    }
};

/// Get the executable info as an unmanaged executable information structure.
pub inline fn asUnmanaged(self: *Managed) *Unmanaged {
    return &self.unmanaged;
}

pub inline fn next(self: *Managed) *Managed {
    const node = self.node.next orelse return null;

    return @fieldParentPtr("node", node);
}

pub inline fn prev(self: *Managed) *Managed {
    const node = self.node.prev orelse return null;

    return @fieldParentPtr("node", node);
}

pub inline fn kernel() *const Unmanaged {
    return &kernel_exe.unmanaged;
}

pub fn getExecutableFromAddress(addr: usize) ?*Unmanaged {
    var exe = &kernel_exe.unmanaged;

    for (0..loaded_executable_count) |_| {
        const base = @intFromPtr(exe.base);

        if (addr > @intFromPtr(exe.base) and addr < (base + exe.size)) break;

        exe = (exe.asManaged().next() orelse break).asUnmanaged();
    }
}
