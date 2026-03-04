const paging = @import("paging.zig");

pub const Pte = packed union {
    raw: u64,
    unknown: packed struct(u64) {
        present: bool,
        _0: u10,
        inlist: bool,
        _1: u50,
        guard: bool,
        _2: u1,
    },
    unset: packed struct(u64) {
        _: u64 = 0,
    },
    present: PresentPte,
    list: ListPte,

    pub inline fn isGuard(self: *const Pte) bool {
        return (!self.unknown.present) and (!self.unknown.inlist) and self.unknown.guard;
    }

    pub inline fn isInList(self: *const Pte) bool {
        return (!self.unknown.present) and self.unknown.inlist;
    }

    pub inline fn isPresent(self: *const Pte) bool {
        return self.unknown.present;
    }

    pub inline fn pfi(self: *const Pte) ?paging.Pfi {
        const vaddr = paging.VirtualAddress.of(self);
        return if (vaddr.pte.addressspace == .recursive_page_tables) vaddr.pte.pfi else null;
    }

    pub inline fn virtAddr(self: *const Pte) ?paging.VirtualAddress {
        const vaddr = paging.VirtualAddress.of(self);
        return if (vaddr.pte.addressspace == .recursive_page_tables) vaddr.pte.pfi.addr() else null;
    }
};

pub const ListPte = packed struct(u64) {
    present: bool = false,
    isblock: bool = false,
    _0: u9 = 0,
    inlist: bool = true,
    _1: u16 = 0,
    next: paging.Pfi,
};

pub const PresentPte = packed struct(u64) {
    present: bool = true,
    writable: bool,
    user: bool,
    write_through: bool,
    disable_cache: bool,
    accessed: bool = false,
    dirty: bool = false,
    huge: bool = false,
    pat: bool = false,
    avail0: u3 = 0,
    addr: u40,
    avail1: u11 = 0,
    no_execute: bool = false,

    pub fn asTable(self: *const @This()) *[512]Pte {
        return @ptrFromInt(self.getAddr());
    }

    pub fn getAddr(self: *const @This()) u64 {
        return self.addr << 12;
    }

    pub fn setAddr(self: *@This(), addr: u64) void {
        self.addr = @intCast(addr >> 12);
    }
};
