const std = @import("std");
const mem = std.mem;

pub const PopupWidget = struct {
    x: usize,
    y: usize,
    width: usize,
    height: usize,
    title: []const u8,
    message: []const u8,
    is_visible: bool,

    pub fn init(x: usize, y: usize, width: usize, height: usize, title: []const u8, message: []const u8) PopupWidget {
        return PopupWidget{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .title = title,
            .message = message,
            .is_visible = false,
        };
    }

    pub fn show(self: *PopupWidget) void {
        self.is_visible = true;
    }

    pub fn hide(self: *PopupWidget) void {
        self.is_visible = false;
    }

    pub fn setMessage(self: *PopupWidget, message: []const u8) void {
        self.message = message;
    }

    pub fn setTitle(self: *PopupWidget, title: []const u8) void {
        self.title = title;
    }

    pub fn clearArea(self: *const PopupWidget, writer: anytype) !void {
        for (0..self.height) |i| {
            try writer.print("\x1B[{d};{d}H", .{ self.y + i, self.x });

            for (0..self.width) |_| {
                try writer.writeAll(" ");
            }
        }
    }

    pub fn render(self: *const PopupWidget, writer: anytype) !void {
        if (!self.is_visible) return;

        try writer.print("\x1B[{d};{d}H", .{ self.y, self.x });
        try writer.writeAll("┌");
        for (0..self.width - 2) |_| {
            try writer.writeAll("─");
        }
        try writer.writeAll("┐");

        if (self.title.len > 0) {
            const title_x = self.x + (self.width - self.title.len) / 2;
            try writer.print("\x1B[{d};{d}H", .{ self.y, title_x });
            try writer.writeAll(self.title);
        }

        for (1..self.height - 1) |i| {
            try writer.print("\x1B[{d};{d}H", .{ self.y + i, self.x });
            try writer.writeAll("│");

            for (0..self.width - 2) |_| {
                try writer.writeAll(" ");
            }

            try writer.print("\x1B[{d};{d}H", .{ self.y + i, self.x + self.width - 1 });
            try writer.writeAll("│");
        }

        try writer.print("\x1B[{d};{d}H", .{ self.y + self.height - 1, self.x });
        try writer.writeAll("└");
        for (0..self.width - 2) |_| {
            try writer.writeAll("─");
        }
        try writer.writeAll("┘");

        var lines = std.mem.splitSequence(u8, self.message, "\n");
        var line_index: usize = 0;
        while (lines.next()) |line| {
            if (line_index >= self.height - 2) break;

            const max_line_width = self.width - 4;
            const display_line = if (line.len > max_line_width) line[0..max_line_width] else line;

            const line_x = self.x + 2;
            try writer.print("\x1B[{d};{d}H", .{ self.y + 1 + line_index, line_x });
            try writer.writeAll(display_line);

            line_index += 1;
        }
    }
};
