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

    pub const cpu_info_and_features: Query = .{
        .leaf = 1,
        .subleaf = 0,
        .registers = .{ .eax, .edx, .ecx, .ebx },
        .type = packed struct {
            stepping_id: u4,
            model: u4,
            family_id: u4,
            process_type: u2,
            reserved1: u2 = 0,
            extended_model_id: u4,
            extended_family_id: u8,
            reserved2: u4 = 0,
            cpu_features: CpuFeatures,
            _: u32 = 0,
        },
    };
};

pub const CpuFeatures = packed struct(u64) {
    fpu: bool,
    vme: bool,
    dbg: bool,
    pse: bool,
    tsc: bool,
    msr: bool,
    pae: bool,
    mce: bool,
    cx8: bool,
    apic: bool,
    _reserved1: u1 = 0,
    sep: bool,
    mtrr: bool,
    pge: bool,
    mca: bool,
    cmov: bool,
    pat: bool,
    pse36: bool,
    psn: bool,
    cflush: bool,
    _reserved2: u1 = 0,
    dtes: bool,
    acpi: bool,
    mmx: bool,
    fxsr: bool,
    sse: bool,
    sse2: bool,
    ss: bool,
    htt: bool,
    tm1: bool,
    ia64: bool,
    pbe: bool,
    sse3: bool,
    pclmul: bool,
    dtes64: bool,
    mon: bool,
    dscpl: bool,
    vmx: bool,
    smx: bool,
    est: bool,
    tm2: bool,
    ssse3: bool,
    cid: bool,
    sdbg: bool,
    fma: bool,
    cx16: bool,
    etprd: bool,
    pdcm: bool,
    _reserved3: u1 = 0,
    pcid: bool,
    dca: bool,
    sse41: bool,
    sse42: bool,
    x2apic: bool,
    movbe: bool,
    popcnt: bool,
    tscd: bool,
    aes: bool,
    xsave: bool,
    osxsave: bool,
    avx: bool,
    f16c: bool,
    rdrand: bool,
    hv: bool,
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
