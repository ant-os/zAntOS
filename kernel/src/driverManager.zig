const std = @import("std");
const ANTSTATUS = @import("status.zig").ANTSTATUS;
const heap = @import("heap.zig");
const filesystem = @import("filesystem.zig");
const callbacks = @import("driverCallbacks.zig");

pub const SimpleKVPairs = extern struct {
    keys: ?[*:0]const u8,
    values: ?[*]const u64,

    pub const none: SimpleKVPairs = .{
        .keys = null,
        .values = null,
    };

    pub inline fn keyNames(comptime T: type) [:0]const u8 {
        var keys: []const u8 = "";

        const fields = std.meta.fields(T);
        inline for (fields) |field| {
            keys = std.fmt.comptimePrint("{s}{s}\xFF", .{ keys, field.name });
        }

        return keys ++ "\x00";
    }

    /// Convert a zig fields into a "SKVPs"(Simple ABI-safe key-value Pairs).
    pub inline fn construct(params: anytype) !SimpleKVPairs {
        // WARNING: DO NOT REMOVE! Otherwiese the compiler's optimization will lead to UB in certain cases.
        _ = std.mem.doNotOptimizeAway(params);

        const fields = std.meta.fields(@TypeOf(params));

        const values = try heap.allocator.alloc(u64, fields.len);

        inline for (fields, 0..) |field, idx| {
            values[idx] = intoRawValue(@field(params, field.name));
        }

        return .{ .keys = @call(.compile_time, keyNames, .{@TypeOf(params)}), .values = values.ptr };
    }

    inline fn intoRawValue(value: anytype) u64 {
        return switch (@typeInfo(@TypeOf(value))) {
            // TODO: Move to seperate functions and extend.
            .int => @intCast(value),
            .pointer => @intFromPtr(value),
            .bool => @intCast(@intFromBool(value)),
            .comptime_int => @intCast(value),
            .null => @intCast(0),
            else => @compileError(std.fmt.comptimePrint("invalid type {s}", .{@typeName(value)})),
        };
    }

    const MAX_SUPPORTED_PAIRS = 50;

    pub fn format(self: *const SimpleKVPairs, writer: anytype) !void {
        try writer.writeAll("{ ");

        if (self.values == null) {
            try writer.writeAll(" }");
            return;
        }

        var offset: u64 = 0;
        var param: []const u8 = undefined;
        var counter: u32 = 0;

        for (0..MAX_SUPPORTED_PAIRS) |idx| {
            param = std.mem.sliceTo(self.keys.?[offset..], '\xFF');

            if (param.len == 0) break;

            if (counter != 0) try writer.writeAll(", ");
            counter += 1;
            offset += param.len + 1;

            if (self.values) |values| {
                try writer.print("{s}=0x{x}", .{
                    param,
                    values[idx],
                });
            } else try writer.writeAll(param);
        }

        try writer.writeAll(" }");
    }

    pub inline fn parseInto(self: SimpleKVPairs, comptime T: type) ANTSTATUS.ZigError!T {
        const FIELDS = @typeInfo(T).@"struct".fields;

        comptime if (FIELDS.len == 0) return;
        comptime if (FIELDS.len > 64) @compileError("more than 64 driver parameters are not supported");

        var offset: u64 = 0;
        var param: []const u8 = undefined;

        var parsed: T = undefined;
        var set = std.bit_set.IntegerBitSet(FIELDS.len).initEmpty();

        inline for (FIELDS, 0..) |field, fidx| {
            if (field.defaultValue()) |def| {
                set.set(fidx);
                @field(parsed, field.name) = def;
            }
        }

        if (self.keys) |keys| {
            parse: for (0..255) |index| {
                const values = self.values orelse break :parse;

                param = std.mem.sliceTo(keys[offset..], '\xFF');

                if (param.len == 0) break;

                offset += param.len + 1;
                inline for (FIELDS, 0..) |field, fidx| {
                    comptime if (@sizeOf(field.type) > @sizeOf(u64)) {
                        @compileError(std.fmt.comptimePrint("size of the driver parameter '{s}' is too large.", .{field.name}));
                    };
                    if (std.ascii.eqlIgnoreCase(param, field.name)) {
                        const fieldty = @typeInfo(field.type);

                        const value: field.type = switch (fieldty) {
                            .int => @truncate(values[index]),
                            .pointer => @ptrFromInt(values[index]),
                            .@"enum" => |enu| blk: {
                                if (enu.is_exhaustive) @compileError(std.fmt.comptimePrint(
                                    "enum as driver parameter is exhaustive {s}",
                                    .{@typeName(field.type)},
                                ));

                                break :blk @as(field.type, @enumFromInt(values[index]));
                            },
                            .bool => values[index] != 0,
                            .void => continue :parse,
                            else => |t| {
                                @compileError(std.fmt.comptimePrint(
                                    "the type {s} is not valid for a driver parameter",
                                    .{@typeName(@Type(t))},
                                ));
                            },
                        };

                        set.set(fidx);
                        @field(parsed, field.name) = value;
                    }
                }
            }
        }

        if (set.count() != FIELDS.len) return error.InvalidParameter;

        return parsed;
    }
};

pub const DriverObject = extern struct {
    display_name: [255]u8,
    global_parameters: SimpleKVPairs,
    callbacks: [callbacks.MAXIMUM_INDEX + 1]usize,

    pub inline fn setCallback(
        self: *DriverObject,
        comptime cb: callbacks.Callback,
        func: *const cb.signature,
    ) void {
        self.callbacks[cb.idx] = @intFromPtr(func);
    }
};

pub const ParameterDesc = extern struct {
    name: [*]const u8,
    name_len: u32,
    value: u64,

    pub fn new(name: []const u8, value: u64) ParameterDesc {
        return .{
            .name = name.ptr,
            .name_len = @intCast(name.len),
            .value = value,
        };
    }

    pub inline fn getName(self: ParameterDesc) []const u8 {
        return self.name[0..self.name_len];
    }
};

pub const DriverType = enum {
    generic,
    char,
    block,
    filesystem,
};

pub const DriverInitFunc = fn (*DriverObject) callconv(.c) ANTSTATUS;

pub const DriverDescriptor = struct {
    node: std.DoublyLinkedList.Node,
    resources: std.DoublyLinkedList,
    resource_count: u64,
    object: *DriverObject,
    init_func: *const DriverInitFunc,
    type_: DriverType,

    pub fn init(self: *const DriverDescriptor) !void {
        try self.init_func(self.object).intoZigError();
    }

    pub fn setCallback(
        self: *const DriverDescriptor,
        comptime cb: callbacks.Callback,
        func: *const cb.signature,
    ) !void {
        if (cb.driver_ty != .generic and cb.driver_ty != self.type_)
            return error.InvalidParameter;

        self.object.setCallback(cb, func);
    }

    pub inline fn callback(
        self: *const DriverDescriptor,
        comptime cb: callbacks.Callback,
    ) ?*const cb.signature {
        if (cb.driver_ty != .generic and cb.driver_ty != self.type_) return null;

        return @ptrFromInt(self.object.callbacks[cb.idx]);
    }
};

var driver_nodes: std.DoublyLinkedList = .{};
var drivers: u32 = 0;

var empty_params = [0]ParameterDesc{};

pub inline fn toParameters(param_block: anytype) []ParameterDesc {
    const param_count = @typeInfo(param_block).@"struct".fields;
    if (param_count == 0) return empty_params[0..];

    var params: [param_count]ParameterDesc = undefined;

    inline for (@typeInfo(param_block).@"struct".fields, 0..) |field, idx| {
        params[idx] = .{
            .name = undefined,
            .name_len = field.name.len,
            .value = @bitCast(@field(param_block, field.name)),
        };
    }

    return params;
}

pub fn register(
    name: []const u8,
    type_: DriverType,
    init_fn: *const DriverInitFunc,
    paramters: ?[*]const ParameterDesc,
    param_count: usize,
) !*DriverDescriptor {
    var desc = try heap.allocator.create(DriverDescriptor);

    desc.* = std.mem.zeroInit(DriverDescriptor, desc.*);

    desc.object = try heap.allocator.create(DriverObject);
    desc.object.* = std.mem.zeroInit(DriverObject, desc.object.*);
    desc.type_ = type_;
    std.mem.copyForwards(u8, &desc.object.display_name, name);
    if (paramters != null and param_count != 0) {
        desc.object.global_parameters = .none;
    }
    desc.init_func = init_fn;
    drivers += 1;

    driver_nodes.append(&desc.node);

    return @ptrCast(desc);
}
