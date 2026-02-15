//! Spin Lock (dummy)

const std = @import("std");
const logger = @import("../logger.zig");

pub const SpinLock = extern struct {
    locked: std.atomic.Value(bool) align(4) = .init(false),

    pub fn tryLock(self: *SpinLock) bool {
        return self.locked.cmpxchgWeak(
            false,
            true,
            .seq_cst,
            .seq_cst,
        ) == null;
    }

    pub fn isLocked(self: *const SpinLock) bool {
        return self.locked.load(.monotonic);
    }

    pub fn lock(self: *SpinLock) void {
        var count: usize = 0;
        while (!self.tryLock()) : (count += 1) {
            if (count >= 100000) @trap();
            std.atomic.spinLoopHint();
        }
    }

    pub fn unlock(self: *SpinLock) void {
        std.debug.assert(self.locked.swap(false, .seq_cst));
    }
};
