const std = @import("std");

pub const Status = packed struct {
    code: u32,
    reserved: u16 = 0,
    kind: Kind,

    const SUCCESS: Status = .fromU64(0x0);

    pub inline fn err(code: ErrorCode) @This() {
        return .{
            .kind = .err,
            .code = @intFromEnum(code),
        };
    }

    pub const Kind = enum(u16) {
        success = 0,
        err = 0x7000,
        info = 0x4000, // unused
        _,
    };

    pub const SuccessCode = enum(u32) {
        ok = 0,
        _,
    };

    pub const ErrorCode = enum(u32) {
        general_error,
        ummappable_region,
        permission_denied,
        not_found,
        invalid_alignement,
        _,
    };

    pub inline fn asError(self: @This()) ?ErrorCode {
        if (self.kind != .err) return null;

        return @enumFromInt(self.code);
    }

    pub inline fn intoZigError(self: Status) !void {
        const err_: ErrorCode = self.asError() orelse return;
        switch (err_) {
            .general_error => return error.GeneralError,
            .ummappable_region => return error.UnmappableRegion,
            .permission_denied => return error.PermissionDenied,
            .invalid_alignement => return error.InvalidAlignment,
            .not_found => return error.NotFound,
            _ => return error.UnknownError,
        }
    }

    pub inline fn asU64(self: Status) u64 {
        return @bitCast(self);
    }

    pub inline fn fromU64(raw: u64) Status {
        return @bitCast(raw);
    }

    comptime {
        if (@sizeOf(Status) != @sizeOf(u64))
            @compileError("zig status type not same size as u64.");
    }

    pub fn format(
        self: *const Status,
        writer: anytype,
    ) !void {
        var kind_buf: [8]u8 = undefined;

        var code_buf: [255]u8 = undefined;
        const kind = std.ascii.upperString(&kind_buf, @tagName(self.kind));

        if (kind.len <= 1 and self.asU64() != 0) {
            try writer.print("0x{x}", .{self.asU64()});
            return;
        }

        const code = std.ascii.upperString(&code_buf, switch (self.kind) {
            .err => @tagName(self.asError().?),
            else => "_",
        });

        if (code.len <= 1 and self.asU64() != 0) {
            try writer.print("0x{x}", .{self.asU64()});
            return;
        }

        if (self.asU64() == 0) {
            try writer.print("ANTSTATUS_SUCCESS", .{});
        } else {
            try writer.print("ANTSTATUS_{s}_{s}", .{ kind, code });
        }
    }
};
