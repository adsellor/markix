const std = @import("std");
const mem = std.mem;
const text = @import("Text.zig");
const ScrollView = @import("ScrollView.zig").ScrollView;

pub const TextListWidget = struct {
    items: []const []const u8,
    x: usize,
    y: usize,
    width: usize,
    height: usize,
    selected_index: ?usize,
    scroll_view: ?*ScrollView,

    pub fn init(items: []const []const u8, x: usize, y: usize, width: usize, height: usize) TextListWidget {
        return TextListWidget{
            .items = items,
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .selected_index = null,
            .scroll_view = null,
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
            .scroll_view = null,
        };
    }

    pub fn setScrollView(self: *TextListWidget, scroll_view: *ScrollView) void {
        self.scroll_view = scroll_view;
        scroll_view.content_height = self.items.len;
    }

    pub fn render(self: *const TextListWidget, writer: anytype) !void {
        const scroll_offset = if (self.scroll_view) |sv| sv.scroll_offset else 0;
        const visible_items = if (self.height > self.items.len - scroll_offset)
            self.items.len - scroll_offset
        else
            self.height;

        for (0..self.height) |i| {
            try writer.print("\x1B[{d};{d}H", .{ self.y + i + 1, self.x + 1 });
            try writer.writeAll(" " ** 50);
        }

        for (0..visible_items) |i| {
            const item_index = i + scroll_offset;
            if (item_index >= self.items.len) break;

            const item = self.items[item_index];
            const is_selected = if (self.selected_index) |idx| idx == item_index else false;

            try writer.print("\x1B[{d};{d}H", .{ self.y + i + 1, self.x + 1 });
            if (is_selected) {
                try writer.writeAll("> ");
            } else {
                try writer.writeAll("  ");
            }

            const display_width = self.width - 2;
            if (item.len > display_width) {
                try writer.writeAll(item[0..display_width]);
            } else {
                try writer.writeAll(item);
            }
        }

        if (self.scroll_view) |sv| {
            try sv.render(writer);
        }
    }

    pub fn setSelectedIndex(self: *TextListWidget, index: ?usize) void {
        self.selected_index = index;
        if (index) |idx| {
            if (self.scroll_view) |sv| {
                sv.scrollToIndex(idx);
            }
        }
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

        if (new_index < 0) {
            new_index = @intCast(self.items.len - 1);
        } else if (new_index >= self.items.len) {
            new_index = 0;
        }

        self.selected_index = @intCast(new_index);

        if (self.scroll_view) |sv| {
            sv.scrollToIndex(self.selected_index.?);
        }
    }
};
