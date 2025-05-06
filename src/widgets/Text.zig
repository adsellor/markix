const std = @import("std");
const mem = std.mem;

pub const TextWidget = struct {
    content: []const u8,
    x: usize,
    y: usize,
    width: usize,
    height: usize,

    pub fn init(content: []const u8, x: usize, y: usize, width: usize, height: usize) TextWidget {
        return TextWidget{
            .content = content,
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        };
    }

    pub fn render(self: *const TextWidget, writer: anytype) !void {
        try writer.print("\x1B[{d};{d}H", .{ self.y + 1, self.x + 1 });

        var lines = mem.splitScalar(u8, self.content, '\n');

        var line_count: usize = 0;
        while (lines.next()) |line| : (line_count += 1) {
            if (line_count >= self.height) break;

            const display_line = if (line.len > self.width)
                line[0..self.width]
            else
                line;

            try writer.print("\x1B[{d};{d}H", .{ self.y + line_count + 1, self.x + 1 });

            try writer.writeAll(display_line);
        }
    }
};
