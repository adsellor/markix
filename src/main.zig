const std = @import("std");
const mem = std.mem;
const Color = @import("layout/Color.zig").Color;
const terminal = @import("layout/Canvas.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try terminal.TerminalCanvas.enterAlternateScreen();
    defer terminal.TerminalCanvas.exitAlternateScreen() catch {};

    var canvas = try terminal.TerminalCanvas.initAutoSize(allocator);
    defer canvas.deinit();

    canvas.setRefreshLimit(120);

    const white = Color.fromRgb(255, 255, 255);
    const bg_color = Color.fromRgb(10, 10, 40);

    var frame_count: u32 = 0;

    while (true) {
        var pollfds = [_]std.posix.pollfd{
            .{ .fd = 0, .events = std.posix.POLL.IN, .revents = 0 },
        };

        const poll_result = try std.posix.poll(&pollfds, 0);

        if (poll_result > 0 and (pollfds[0].revents & std.posix.POLL.IN) != 0) {
            const event = try terminal.readEvent(std.io.getStdIn().reader());
            if (event == .Key and event.Key == 'q') {
                break;
            }
        }

        canvas.clear();
        canvas.clearText();

        for (0..canvas.width) |x| {
            for (0..canvas.height) |y| {
                canvas.setPixel(@intCast(x), @intCast(y), bg_color);
            }
        }

        const wave_y = 70;

        for (0..canvas.width) |x| {
            const wave_offset = @as(i32, @intFromFloat(8.0 * @sin(@as(f32, @floatFromInt(frame_count)) / 15.0 +
                @as(f32, @floatFromInt(x)) / 20.0)));

            const pos_y = @as(i32, @intCast(wave_y)) + wave_offset;
            if (pos_y >= 0 and pos_y < canvas.height) {
                const hue = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(canvas.width)) * 360.0 +
                    @as(f32, @floatFromInt(frame_count));
                const r = @as(u8, @intFromFloat(127.5 + 127.5 * @sin(hue * std.math.pi / 180.0)));
                const g = @as(u8, @intFromFloat(127.5 + 127.5 * @sin((hue + 120.0) * std.math.pi / 180.0)));
                const b = @as(u8, @intFromFloat(127.5 + 127.5 * @sin((hue + 240.0) * std.math.pi / 180.0)));

                canvas.setPixel(@intCast(x), @intCast(pos_y), Color.fromRgb(r, g, b));
            }
        }

        try canvas.addText(10, 1, "This text is rendered the terminal", white, bg_color);
        try canvas.addText(10, 2, "while the wave is rendered by the canvas.", white, bg_color);

        var fps_buf: [20]u8 = undefined;
        const fps_text = try std.fmt.bufPrint(&fps_buf, "Target FPS: {d}", .{120});
        try canvas.addText(@intCast(canvas.width - 30), 1, fps_text, white, bg_color);

        try canvas.render();

        frame_count += 1;
    }
}
