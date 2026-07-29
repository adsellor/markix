const std = @import("std");
const input = @import("../input.zig");

pub const Action = enum { ignored, changed, submitted, cancelled };

pub fn TextInput(comptime capacity: u16) type {
    return struct {
        const Self = @This();

        bytes: [capacity]u8 = undefined,
        length: u16 = 0,
        cursor: u16 = 0,

        pub fn value(self: *const Self) []const u8 {
            return self.bytes[0..self.length];
        }

        pub fn set(self: *Self, value_bytes: []const u8) !void {
            if (value_bytes.len > capacity) return error.TextTooLong;
            @memcpy(self.bytes[0..value_bytes.len], value_bytes);
            self.length = @intCast(value_bytes.len);
            self.cursor = self.length;
        }

        pub fn clear(self: *Self) void {
            self.length = 0;
            self.cursor = 0;
        }

        pub fn handle(self: *Self, key: input.Key) !Action {
            return switch (key) {
                .character => |byte| self.insert(byte),
                .backspace => self.backspace(),
                .delete => self.delete(),
                .left => self.move_left(),
                .right => self.move_right(),
                .home => self.move_home(),
                .end => self.move_end(),
                .enter => .submitted,
                .escape => .cancelled,
                else => .ignored,
            };
        }

        fn insert(self: *Self, byte: u8) !Action {
            if (!std.ascii.isPrint(byte)) return .ignored;
            if (self.length >= capacity) return error.TextInputFull;
            var index = self.length;
            while (index > self.cursor) : (index -= 1) {
                self.bytes[index] = self.bytes[index - 1];
            }
            self.bytes[self.cursor] = byte;
            self.length += 1;
            self.cursor += 1;
            return .changed;
        }

        fn backspace(self: *Self) Action {
            if (self.cursor == 0) return .ignored;
            self.cursor -= 1;
            return self.remove_at_cursor();
        }

        fn delete(self: *Self) Action {
            if (self.cursor >= self.length) return .ignored;
            return self.remove_at_cursor();
        }

        fn remove_at_cursor(self: *Self) Action {
            var index = self.cursor;
            while (index + 1 < self.length) : (index += 1) {
                self.bytes[index] = self.bytes[index + 1];
            }
            self.length -= 1;
            return .changed;
        }

        fn move_left(self: *Self) Action {
            self.cursor -|= 1;
            return .changed;
        }

        fn move_right(self: *Self) Action {
            self.cursor = @min(self.cursor +| 1, self.length);
            return .changed;
        }

        fn move_home(self: *Self) Action {
            self.cursor = 0;
            return .changed;
        }

        fn move_end(self: *Self) Action {
            self.cursor = self.length;
            return .changed;
        }
    };
}

test "text input edits at its cursor" {
    var field = TextInput(8){};
    try field.set("ac");
    _ = try field.handle(.left);
    _ = try field.handle(.{ .character = 'b' });
    try std.testing.expectEqualStrings("abc", field.value());
    try std.testing.expectEqual(Action.changed, try field.handle(.backspace));
    try std.testing.expectEqualStrings("ac", field.value());
}
