const std = @import("std");

pub fn isAbsolute(path: []const u8) bool {
    if (path.len < 1) return false;
    return path[0] == '/';
}

pub fn basename(path: []const u8) ?[]const u8 {
    if (path.len == 0) return null;
    if (path[path.len - 1] == '/') return null;

    const lastSeperator = if(std.mem.lastIndexOfScalar(
        u8,
        path,
        '/',
    )) |idx| (idx + 1) else 0;
    
    return path[lastSeperator..];
}

pub fn dirname(path: []const u8) []const u8 {
    const lastSeperator = if(std.mem.lastIndexOfScalar(
        u8,
        path,
        '/',
    )) |idx| (idx + 1) else 0;

    return path[0..(lastSeperator)];
}
