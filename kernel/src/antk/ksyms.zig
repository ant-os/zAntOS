const std = @import("std");
const antk = @import("antk.zig");

const StructField = std.builtin.Type.StructField;

pub const _KernelSymbolCollection = blk: {
    var buffer: [100]std.builtin.Type.StructField = undefined;
    var list = std.ArrayList(std.builtin.Type.StructField).initBuffer(&buffer);
    discoverSymbolsRecusive(antk, &list);
    break :blk @Type(.{
        .@"struct" = .{
            .fields = list.items,
            .decls = &.{},
            .layout = .auto,
            .is_tuple = false,
        },
    });
};

pub fn discoverSymbolsRecusive(comptime T: type, list: *std.ArrayList(StructField)) void {
    const info = @typeInfo(T);

    if (info != .@"struct") return .{};

    for (info.@"struct".decls) |decl| {
        if (std.mem.eql(u8, decl.name, "c") or std.mem.eql(u8, decl.name, "internal")) continue;

        const declType = @typeInfo(@TypeOf(@field(T, decl.name)));

        switch (declType) {
            .@"struct" => discoverSymbolsRecusive(@TypeOf(@field(T, decl.name)), list),
            .comptime_float, .comptime_int, .enum_literal, .error_set, .error_union, .type, .undefined => continue,
            else => if (@hasDecl(antk.c, decl.name)) (list.appendBounded(.{
                .is_comptime = true,
                .name = decl.name,
                .type = type,
                .alignment = @alignOf(type),
                .default_value_ptr = @ptrCast(&T),
            }) catch @compileError("too many kernel symbols")) else continue,
        }
    }
}
