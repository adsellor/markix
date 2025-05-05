const std = @import("std");
const mem = std.mem;

pub const ScrollView = struct {
    x: usize,
    y: usize,
    width: usize,
    height: usize,
    content_height: usize,
    scroll_offset: usize,

    pub fn init(x: usize, y: usize, width: usize, height: usize, content_height: usize) ScrollView {
        return ScrollView{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .content_height = content_height,
            .scroll_offset = 0,
        };
    }

    pub fn scrollUp(self: *ScrollView) void {
        if (self.scroll_offset > 0) {
            self.scroll_offset -= 1;
        }
    }

    pub fn scrollDown(self: *ScrollView) void {
        if (self.scroll_offset + self.height < self.content_height) {
            self.scroll_offset += 1;
        }
    }

    pub fn scrollToIndex(self: *ScrollView, index: usize) void {
        if (index >= self.content_height) return;

        if (index < self.scroll_offset) {
            self.scroll_offset = index;
        } else if (index >= self.scroll_offset + self.height) {
            self.scroll_offset = index - self.height + 1;
        }
    }

    pub fn render(self: *const ScrollView, writer: anytype) !void {
        if (self.content_height > self.height) {
            if (self.scroll_offset > 0) {
                try writer.print("\x1B[{d};{d}H", .{ self.y, self.x + self.width - 1 });
                try writer.writeAll("↑");
            }

            if (self.scroll_offset + self.height < self.content_height) {
                try writer.print("\x1B[{d};{d}H", .{ self.y + self.height, self.x + self.width - 1 });
                try writer.writeAll("↓");
            }
        }
    }
};
