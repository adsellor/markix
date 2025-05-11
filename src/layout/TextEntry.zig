const std = @import("std");
const Color = @import("Color.zig").Color;

const mem = std.mem;
const Allocator = std.mem.Allocator;

pub const TextEntry = struct {
    x: u32,
    y: u32,
    text: []const u8,
    foreground_color: Color,
    background_color: ?Color = null,

    pub fn deinit(self: *TextEntry, allocator: Allocator) void {
        allocator.free(self.text);
    }

    pub fn clone(self: *const TextEntry, allocator: Allocator) !TextEntry {
        const text_copy = try allocator.alloc(u8, self.text.len);
        @memcpy(text_copy, self.text);

        return TextEntry{
            .x = self.x,
            .y = self.y,
            .text = text_copy,
            .foreground_color = self.foreground_color,
            .background_color = self.background_color,
        };
    }

    pub fn equals(self: *const TextEntry, other: *const TextEntry) bool {
        if (self.x != other.x or self.y != other.y) return false;
        if (!self.foreground_color.equals(other.foreground_color)) return false;

        const self_bg = self.background_color orelse Color.fromRgba(0, 0, 0, 0);
        const other_bg = other.background_color orelse Color.fromRgba(0, 0, 0, 0);
        if (!self_bg.equals(other_bg)) return false;

        return mem.eql(u8, self.text, other.text);
    }
};
