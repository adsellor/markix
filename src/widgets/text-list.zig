const std = @import("std");
const mem = std.mem;
const text = @import("text.zig");

pub const TextListWidget = struct {
    items: []const []const u8,
    x: usize,
    y: usize,
    width: usize,
    height: usize,
    selected_index: ?usize,

    pub fn init(items: []const []const u8, x: usize, y: usize, width: usize, height: usize) TextListWidget {
        return TextListWidget{
            .items = items,
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .selected_index = null,
        };
    }

    pub fn initWithSelection(items: []const []const u8, x: usize, y: usize, width: usize, height: usize, selected_index: usize) TextListWidget {
        return TextListWidget{
            .items = items,
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .selected_index = selected_index,
        };
    }

    pub fn render(self: *const TextListWidget, writer: anytype) !void {
        const visible_items = if (self.items.len > self.height) self.height else self.items.len;

        for (0..visible_items) |i| {
            const item = self.items[i];
            const is_selected = if (self.selected_index) |idx| idx == i else false;
            try writer.print("\x1B[{d};{d}H", .{ self.y + i + 1, self.x + 1 });

            if (is_selected) {
                try writer.writeAll("> ");
            } else {
                try writer.writeAll("  ");
            }

            try writer.writeAll(item);
        }
    }

    pub fn setSelectedIndex(self: *TextListWidget, index: ?usize) void {
        self.selected_index = index;
    }

    pub fn getSelectedItem(self: *const TextListWidget) ?[]const u8 {
        if (self.selected_index) |idx| {
            if (idx < self.items.len) {
                return self.items[idx];
            }
        }
        return null;
    }

    pub fn moveSelection(self: *TextListWidget, delta: isize) void {
        if (self.items.len == 0) return;

        const current = self.selected_index orelse 0;
        var new_index: isize = @intCast(current);
        new_index += delta;

        // Handle wrapping
        if (new_index < 0) {
            new_index = @intCast(self.items.len - 1);
        } else if (new_index >= self.items.len) {
            new_index = 0;
        }

        self.selected_index = @intCast(new_index);
    }
};
