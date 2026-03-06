const std = @import("std");

pub const eax_0: Query = .{
    .leaf = 0,
    .subleaf = 0,
    .registers = .{
        .eax,
        .ebx,
        .edx,
        .ecx,
    },
    .type = extern struct {
        highest_func: u32,
        vendor: [12]u8,
    },
};

pub const freq_1: Query = .{
    .leaf = 0x15,
    .subleaf = 0,
    .registers = .{
        .eax,
        .ebx,
        .ecx,
        .edx,
    },
    .type = extern struct {
        tsc_ratio_denominator: u32,
        tsc_ratio_numerator: u32,
        core_freq_hz: u32,
        _: u32,
    },
};

pub const freq_2: Query = .{
    .leaf = 0x16,
    .subleaf = 0,
    .registers = .{
        .eax,
        .ebx,
        .ecx,
        .edx,
    },
    .type = extern struct {
        base_hz: u32,
        maximum_hz: u32,
        refrence_hz: u32,
        _: u32,
    },
};

pub const hypervisor_id: Query = .{
    .leaf = 0x16,
    .subleaf = 0,
    .registers = .{
        .ebx,
        .ecx,
        .edx,
        .eax,
    },
    .type = extern struct {
        vendor_id: [12]u8 align(4),
        _unused: u32 = 0,
    },
};

pub const Query = struct {
    pub const ResultRegisters = struct {
        eax: u32,
        ebx: u32,
        edx: u32,
        ecx: u32,
    };

    leaf: u32,
    subleaf: u64,
    registers: [4]std.meta.FieldEnum(ResultRegisters),
    type: type,
};

pub inline fn cpuid(comptime query: Query) query.type {
    if (@sizeOf(query.type) > 16) @compileError("type is too large");
    var result: query.type align(16) = std.mem.zeroes(query.type);
    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var edx: u32 = undefined;
    var ecx: u32 = undefined;

    asm volatile ("cpuid"
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [edx] "={edx}" (edx),
          [ecx] "={ecx}" (ecx),
        : [leaf] "{eax}" (query.leaf),
          [subleaf] "{ecx}" (query.subleaf),
    );

    const regs = Query.ResultRegisters{
        .eax = eax,
        .ebx = ebx,
        .ecx = ecx,
        .edx = edx,
    };

    const array: [*]const u8 = @ptrCast(&[4]u32{
        @field(regs, @tagName(query.registers[0])),
        @field(regs, @tagName(query.registers[1])),
        @field(regs, @tagName(query.registers[2])),
        @field(regs, @tagName(query.registers[3])),
    });

    @memcpy(std.mem.asBytes(&result), array[0..@sizeOf(query.type)]);
    
    return result;
}
