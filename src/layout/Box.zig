const std = @import("std");
const Color = @import("Color.zig").Color;
const Allocator = std.mem.Allocator;

pub const Box = struct {
    width: u16,
    height: u16,
    x: u16,
    y: u16,
    parent: ?*Box,
    background_color: Color,
    children: std.ArrayList(*Box),
    allocator: Allocator,

    pub fn init(allocator: Allocator, width: u16, height: u16, x: u16, y: u16, background_color: Color) !*Box {
        const box = try allocator.create(Box);
        box.* = Box{
            .width = width,
            .height = height,
            .x = x,
            .y = y,
            .parent = null,
            .background_color = background_color,
            .children = std.ArrayList(*Box).init(allocator),
            .allocator = allocator,
        };
        return box;
    }

    pub fn deinit(self: *Box) void {
        for (self.children.items) |child| {
            child.deinit();
        }
        self.children.deinit();
        self.allocator.destroy(self);
    }

    pub fn addChild(self: *Box, child: *Box) !void {
        child.parent = self;
        try self.children.append(child);
    }

    fn calculatePosX(self: *Box) void {
        if (self.parent) |parent| {
            if (self.width >= parent.width) {
                self.x = parent.x;
            } else {
                self.x = parent.x + (parent.width - self.width) / 2;
            }
        }
    }

    fn calculatePosY(self: *Box) void {
        if (self.parent) |parent| {
            if (self.height >= parent.height) {
                self.y = parent.y;
            } else {
                self.y = parent.y + (parent.height - self.height) / 2;
            }
        }
    }

    pub fn updatePositions(self: *Box) void {
        if (self.parent != null) {
            self.calculatePosX();
            self.calculatePosY();
        }

        for (self.children.items) |child| {
            child.updatePositions();
        }
    }

    pub fn resize(self: *Box, new_width: u16, new_height: u16) void {
        self.width = new_width;
        self.height = new_height;
        self.updatePositions();
    }

    pub fn render(self: *Box, canvas: anytype) void {
        canvas.filledRect(self.x, self.y, self.width, self.height, self.background_color);

        for (self.children.items) |child| {
            child.render(canvas);
        }
    }
};
