//! AntOS C-Safe Status Code.
// NOTE: Not a source file struct as it needs to be packed.

const std = @import("std");

comptime {
    if (@sizeOf(ANTSTATUS) != @sizeOf(u64) or @alignOf(ANTSTATUS) != @alignOf(u64))
        @compileError("CRITCIAL: ANTSTATUS is not longer ABI-compatible.");
}

/// ABI-safe status code for errors/etc.
pub const ANTSTATUS = packed struct {
    code: u32,
    reserved: u16 = 0,
    kind: Kind,

    pub const SUCCESS: ANTSTATUS = .fromU64(0x0);

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
        not_mapped,
        bitmap_corrupted,
        out_of_memory,
        permission_denied,
        not_found,
        invalid_alignment,
        invalid_parameter,
        unsupported_operation,
        not_yet_implemented,
        out_of_bounds,
        invalid_handle,
        _,
    };

    /// Zig Error Set for ANTSTATUS Errors.
    pub const ZigError = @call(.compile_time, internal.generateErrorSet, .{}) || error{UnknownError};

    pub inline fn asError(self: @This()) ?ErrorCode {
        if (self.kind != .err) return null;

        return @enumFromInt(self.code);
    }

    /// Convert from ANTSTATUS to a zig error union where if self is an error
    /// the corresponding error is returned as ZIG ERROR.
    pub inline fn intoZigError(self: ANTSTATUS) ZigError!void {
        const err_: ErrorCode = self.asError() orelse return;

        inline for (internal.ERROR_CODE_VARIANTS) |cerr| {
            if (err_ == @field(ErrorCode, cerr.name)) {
                return internal.getZigErrorByCodeName(cerr.name);
            }
        }
        return error.UnknownError;
    }

    /// Converts a Zig Error into an ANTSTATUS value.
    pub inline fn fromZigError(e: ZigError) ANTSTATUS {
        inline for (internal.ERROR_CODE_VARIANTS) |cerr| {
            if (e == internal.getZigErrorByCodeName(cerr.name)) {
                return .err(@field(ErrorCode, cerr.name));
            }
        }

        return .err(.general_error);
    }

    pub inline fn asU64(self: ANTSTATUS) u64 {
        return @bitCast(self);
    }

    pub inline fn fromU64(raw: u64) ANTSTATUS {
        return @bitCast(raw);
    }

    pub fn format(
        self: *const ANTSTATUS,
        writer: anytype,
    ) !void {
        // TODO: This should be allocated on the heap perhaps?
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

const internal = struct {
    /// Maximum supported number of character in a single word.
    const MAX_SUPPORTED_WORD_LEN = 50;
    /// Alias for getting the field of ErrorCode.
    const ERROR_CODE_VARIANTS = @typeInfo(ANTSTATUS.ErrorCode).@"enum".fields;
    /// Comptime helper to translate all raw error codes into a zig error set.
    pub inline fn generateErrorSet() type {
        var zig_errors: [ERROR_CODE_VARIANTS.len]std.builtin.Type.Error = undefined;

        for (ERROR_CODE_VARIANTS, 0..) |err_, idx| {
            var zig_err_buf = std.mem.zeroes([err_.name.len + 1]u8);
            zig_errors[idx] = .{ .name = internal.convertToZigErrorName(&zig_err_buf, err_.name)[0.. :0] };
        }

        return @Type(.{ .error_set = &zig_errors });
    }

    /// Convert snake_case code name into zig ErrorName (TitleCase).
    pub inline fn convertToZigErrorName(comptime buffer: []u8, comptime name: []const u8) []u8 {
        @setEvalBranchQuota(5000);
        if (buffer.len < name.len) {
            @compileError("buffer too small");
        }

        var zig_err = std.ArrayList(u8).initBuffer(buffer);
        var word_buf: [MAX_SUPPORTED_WORD_LEN]u8 = undefined;
        var iter = std.mem.splitSequence(u8, name, "_");

        while (iter.next()) |word| {
            // limit the length of a single word to allow for `word_buf` to be allocated once with a fixed size.
            if (word.len > MAX_SUPPORTED_WORD_LEN) @compileError(std.fmt.comptimePrint(
                "error variant name \"{s}\" is longer than the maximum lenght of {d}",
                .{ word, MAX_SUPPORTED_WORD_LEN },
            ));
            @memcpy(word_buf[0..word.len], word);
            word_buf[0] = std.ascii.toUpper(word[0]);
            zig_err.appendSliceAssumeCapacity(word_buf[0..word.len]);
        }

        return zig_err.items;
    }

    pub inline fn getZigErrorByCodeName(comptime codename: []const u8) ANTSTATUS.ZigError {
        comptime var zig_err_buf = std.mem.zeroes([codename.len + 1]u8);
        return @field(ANTSTATUS.ZigError, internal.convertToZigErrorName(&zig_err_buf, codename));
    }
};
