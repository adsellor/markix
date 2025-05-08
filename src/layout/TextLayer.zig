const std = @import("std");
const Color = @import("Color.zig").Color;

pub const TextLayer = struct {
    pub const TextEntry = struct {
        x: u16,
        y: u16,
        text: []const u8,
        foreground_color: Color,
        background_color: ?Color = null,

        pub fn deinit(self: *TextEntry, allocator: std.mem.Allocator) void {
            allocator.free(self.text);
        }
    };

    entries: std.ArrayList(TextEntry),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TextLayer {
        return .{
            .entries = std.ArrayList(TextEntry).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TextLayer) void {
        for (self.entries.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.entries.deinit();
    }

    pub fn clear(self: *TextLayer) void {
        for (self.entries.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.entries.clearRetainingCapacity();
    }

    pub fn addText(self: *TextLayer, x: u16, y: u16, text: []const u8, fg: Color, bg: ?Color) !void {
        const text_copy = try self.allocator.alloc(u8, text.len);
        @memcpy(text_copy, text);

        try self.entries.append(TextEntry{
            .x = x,
            .y = y,
            .text = text_copy,
            .foreground_color = fg,
            .background_color = bg,
        });
    }

    pub fn render(self: *TextLayer, writer: anytype) !void {
        try writer.writeAll("\x1B[0m");

        for (self.entries.items) |entry| {
            try writer.print("\x1B[{d};{d}H", .{ entry.y + 1, entry.x + 1 });
            try writer.print("\x1B[38;2;{d};{d};{d}m", .{ entry.foreground_color.r, entry.foreground_color.g, entry.foreground_color.b });

            if (entry.background_color) |bg| {
                try writer.print("\x1B[48;2;{d};{d};{d}m", .{ bg.r, bg.g, bg.b });
            }

            try writer.writeAll(entry.text);
        }

        try writer.writeAll("\x1B[0m");
    }
};
