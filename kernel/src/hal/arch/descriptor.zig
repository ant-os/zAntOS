pub fn Descriptor(comptime E: type) type {
    return packed struct {
        limit: u16,
        offset: u64,

        pub inline fn entries(self: @This()) []E {
            const count = self.size() / @sizeOf(E);
            const table: [*]E = @ptrFromInt(self.offset);
            return table[0 .. count - 1];
        }

        pub inline fn size(self: @This()) usize {
            return self.limit + 1;
        }

        pub inline fn first(self: @This()) ?*E {
            if (self.size() < @sizeOf(E)) {
                return null;
            } else return @ptrFromInt(self.offset);
        }
    };
}
