const std = @import("std");
const Color = @import("Color.zig").Color;

pub const Box = struct {
    width: u16,
    height: u16,
    x: u16,
    y: u16,
    background_color: Color,

    pub fn init(width: u16, height: u16, x: u16, y: u16, background_color: Color) Box {
        return Box{
            .width = width,
            .height = height,
            .x = x,
            .y = y,
            .background_color = background_color,
        };
    }

    pub fn withSize(self: Box, new_width: u16, new_height: u16) Box {
        return Box{
            .width = new_width,
            .height = new_height,
            .x = self.x,
            .y = self.y,
            .background_color = self.background_color,
        };
    }

    pub fn withPosition(self: Box, new_x: u16, new_y: u16) Box {
        return Box{
            .width = self.width,
            .height = self.height,
            .x = new_x,
            .y = new_y,
            .background_color = self.background_color,
        };
    }

    pub fn withColor(self: Box, new_color: Color) Box {
        return Box{
            .width = self.width,
            .height = self.height,
            .x = self.x,
            .y = self.y,
            .background_color = new_color,
        };
    }

    pub fn calculateCenteredX(self: Box, parent_box: Box) u16 {
        if (self.width >= parent_box.width) {
            return parent_box.x;
        } else {
            return parent_box.x + (parent_box.width - self.width) / 2;
        }
    }

    pub fn calculateCenteredY(self: Box, parent_box: Box) u16 {
        if (self.height >= parent_box.height) {
            return parent_box.y;
        } else {
            return parent_box.y + (parent_box.height - self.height) / 2;
        }
    }

    pub fn centerInParent(self: Box, parent_box: Box) Box {
        return Box{
            .width = self.width,
            .height = self.height,
            .x = self.calculateCenteredX(parent_box),
            .y = self.calculateCenteredY(parent_box),
            .background_color = self.background_color,
        };
    }

    pub fn render(self: Box, canvas: anytype) void {
        canvas.filledRect(
            @as(u32, self.x),
            @as(u32, self.y),
            @as(u32, self.width),
            @as(u32, self.height),
            self.background_color,
        );
    }

    pub fn contains(self: Box, point_x: u16, point_y: u16) bool {
        return point_x >= self.x and point_x < self.x + self.width and
            point_y >= self.y and point_y < self.y + self.height;
    }

    pub fn intersects(self: Box, other: Box) bool {
        return self.x < other.x + other.width and
            self.x + self.width > other.x and
            self.y < other.y + other.height and
            self.y + self.height > other.y;
    }

    pub fn area(self: Box) u32 {
        return @as(u32, self.width) * @as(u32, self.height);
    }

    pub fn equals(self: Box, other: Box) bool {
        return self.width == other.width and
            self.height == other.height and
            self.x == other.x and
            self.y == other.y and
            self.background_color.equals(other.background_color);
    }
};
