const std = @import("std");
const mem = std.mem;
const Color = @import("layout/Color.zig").Color;
const terminal = @import("layout/Canvas.zig");
const event = @import("utils/event.zig");
const terminal_utils = @import("utils/terminal.zig");
const time = std.time;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original_termios = try terminal_utils.enableRawMode();
    defer terminal_utils.disableRawMode(original_termios) catch {};

    try terminal.TerminalCanvas.enterAlternateScreen();
    defer terminal.TerminalCanvas.exitAlternateScreen() catch {};

    var canvas = try terminal.TerminalCanvas.initAutoSize(allocator);
    defer canvas.deinit();

    canvas.setRefreshLimit(120);

    const white = Color.fromRgb(255, 255, 255);
    const green = Color.fromRgb(0, 255, 0);
    const bg_color = Color.fromRgb(10, 10, 10);

    var frame_count: u32 = 0;

    var fps: f32 = 0.0;
    var last_time = time.nanoTimestamp();
    var fps_update_timer: i128 = 0;
    const fps_update_interval: i128 = time.ns_per_s;

    while (true) {
        var pollfds = [_]std.posix.pollfd{
            .{ .fd = 0, .events = std.posix.POLL.IN, .revents = 0 },
        };

        const poll_result = try std.posix.poll(&pollfds, 0);

        if (poll_result > 0 and (pollfds[0].revents & std.posix.POLL.IN) != 0) {
            const target = try event.readEvent(std.io.getStdIn().reader());
            if (target == .Key and target.Key == 'q') {
                break;
            }
        }

        const current_time = time.nanoTimestamp();
        const frame_time = current_time - last_time;
        last_time = current_time;

        fps_update_timer += frame_time;
        if (fps_update_timer >= fps_update_interval) {
            fps = 1.0 / (@as(f32, @floatFromInt(frame_time)) / @as(f32, @floatFromInt(time.ns_per_s)));
            fps_update_timer = 0;
        }

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

        var fps_buf: [40]u8 = undefined;
        const target_fps_text = try std.fmt.bufPrint(&fps_buf, "Target FPS: {d}", .{120});
        try canvas.addText(@intCast(canvas.width - 30), 1, target_fps_text, white, bg_color);

        var real_fps_buf: [40]u8 = undefined;
        const real_fps_text = try std.fmt.bufPrint(&real_fps_buf, "Current FPS: {d:.1}", .{fps});

        var fps_color = green;

        if (fps < 60) {
            const r = @min(255, @as(u8, @intFromFloat(255.0 * (1.0 - fps / 60.0))));
            const g = @min(255, @as(u8, @intFromFloat(255.0 * (fps / 60.0))));
            fps_color = Color.fromRgb(r, g, 0);
        }

        try canvas.addText(@intCast(canvas.width - 30), 2, real_fps_text, fps_color, bg_color);
        frame_count += 1;

        try canvas.render();
    }
}
