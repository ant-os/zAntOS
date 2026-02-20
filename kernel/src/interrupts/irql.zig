//! IRQL

const std = @import("std");
const spinlock = @import("../sync/spin_lock.zig");

pub const Irql = enum(u4) {
    passive = 0x0,
    async = 0x1,
    dispatch = 0x2,
    deferred = 0x3,
    dev_1 = 0x4,
    dev_2 = 0x5,
    dev_3 = 0x6,
    dev_4 = 0x7,
    dev_5 = 0x8,
    dev_6 = 0x9,
    dev_7 = 0xA,
    dev_8 = 0xB,
    sync = 0xC,
    clock = 0xD,
    ipi = 0xE,
    high = 0xF,

    pub inline fn raw(self: Irql) u4 {
        return @intFromEnum(self);
    }

    pub fn assertLessOrEqual(self: Irql, irql: Irql) void {
        if (irql.raw() > self.raw()) @panic("irql not less or equal");
    }

    pub fn assertHigherOrEqual(self: Irql, irql: Irql) void {
        if (irql.raw() < self.raw()) @panic("irql not higher or equal");
    }

    pub fn assertEqual(self: Irql, irql: Irql) void {
        if (irql.raw() != self.raw()) @panic("irql not equal");
    }
};

/// force set the IRQL
pub fn update(irql: Irql) void {
    asm volatile (
        \\mov %[irql], %%cr8
        :
        : [irql] "r" (@intFromEnum(irql)),
    );
}

/// get the current IRQL
pub fn current() Irql {
    const raw = asm volatile (
        \\mov %%cr8, %[irql]
        : [irql] "=r" (-> u4),
    );

    return @enumFromInt(raw);
}

pub inline fn assertLessOrEqual(irql: Irql) void {
    current().assertLessOrEqual(irql);
}

pub inline fn assertEqual(irql: Irql) void {
    current().assertEqual(irql);
}

pub fn raise(irql: Irql) Irql {
    const old = current();

    old.assertHigherOrEqual(irql);

    update(irql);

    return old;
}

pub const Lock = struct {
    
    old_irql: ?Irql = null,
    spinlock: spinlock.SpinLock = .{},

    const default_irql: Irql = .sync;
    pub const init: Lock = .{};

    pub fn lockAt(self: *Lock, irql: Irql) void {
        self.old_irql = raise(irql);
        self.spinlock.lock();
    }

    pub fn lock(self: *Lock) void {
        self.lockAt(default_irql);
    }

    pub fn unlock(self: *Lock) void {
        self.spinlock.unlock();
        update(self.old_irql.?);
    }

    test lock {
        var l = Lock.init;

        l.lock();
        try std.testing.expect(current() == default_irql);
        l.unlock();
    }

    test lockAt {
        var l = Lock.init;

        l.lockAt(.dispatch);
        try std.testing.expect(current() == .dispatch);
        l.unlock();
    }
};

comptime { std.testing.refAllDecls(Lock); }