const std = @import("std");
const terminal = @import("layout/Canvas.zig");
const event = @import("utils/event.zig");
const terminal_utils = @import("utils/terminal.zig");
const Color = @import("layout/Color.zig").Color;

const mem = std.mem;
const time = std.time;
const io = std.io;
const posix = std.posix;
const Event = event.Event;
const TerminalCanvas = terminal.TerminalCanvas;

const AnimationContext = struct {
    canvas: *TerminalCanvas,
    frame_count: u32 = 0,
    fps: f32 = 0.0,
    last_time: i128 = 0,
    fps_update_timer: i128 = 0,
    fps_update_interval: i128 = time.ns_per_s,
};

fn animationCallback(context: *AnimationContext, e: Event) bool {
    if (e == .Key and e.Key == 'q') {
        return false;
    }

    const current_time = time.nanoTimestamp();
    const frame_time = current_time - context.last_time;
    context.last_time = current_time;

    context.fps_update_timer += frame_time;
    if (context.fps_update_timer >= context.fps_update_interval) {
        context.fps = 1.0 / (@as(f32, @floatFromInt(frame_time)) / @as(f32, @floatFromInt(time.ns_per_s)));
        context.fps_update_timer = 0;
    }

    var canvas = context.canvas;

    const white = Color.fromRgb(255, 255, 255);
    const green = Color.fromRgb(0, 255, 0);
    const bg_color = Color.fromRgb(10, 10, 10);

    for (0..canvas.width) |x| {
        for (0..canvas.height) |y| {
            canvas.setPixel(@intCast(x), @intCast(y), bg_color);
        }
    }

    const wave_y = 70;

    for (0..canvas.width) |x| {
        const wave_offset = @as(i32, @intFromFloat(8.0 * @sin(@as(f32, @floatFromInt(context.frame_count)) / 15.0 +
            @as(f32, @floatFromInt(x)) / 20.0)));

        const pos_y = @as(i32, @intCast(wave_y)) + wave_offset;
        if (pos_y >= 0 and pos_y < canvas.height) {
            const hue = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(canvas.width)) * 360.0 +
                @as(f32, @floatFromInt(context.frame_count));
            const r = @as(u8, @intFromFloat(127.5 + 127.5 * @sin(hue * std.math.pi / 180.0)));
            const g = @as(u8, @intFromFloat(127.5 + 127.5 * @sin((hue + 120.0) * std.math.pi / 180.0)));
            const b = @as(u8, @intFromFloat(127.5 + 127.5 * @sin((hue + 240.0) * std.math.pi / 180.0)));

            canvas.setPixel(@intCast(x), @intCast(pos_y), Color.fromRgb(r, g, b));
        }
    }

    canvas.addText(10, 1, "This text is rendered the terminal", white, bg_color) catch {};
    canvas.addText(10, 2, "while the wave is rendered by the canvas.", white, bg_color) catch {};

    var fps_buf: [40]u8 = undefined;
    const target_fps_text = std.fmt.bufPrint(&fps_buf, "Target FPS: {d}", .{120}) catch return true;
    canvas.addText(@intCast(canvas.width - 30), 1, target_fps_text, white, bg_color) catch {};

    var real_fps_buf: [40]u8 = undefined;
    const real_fps_text = std.fmt.bufPrint(&real_fps_buf, "Current FPS: {d:.1}", .{context.fps}) catch return true;

    var fps_color = green;

    if (context.fps < 60) {
        const r = @min(255, @as(u8, @intFromFloat(255.0 * (1.0 - context.fps / 60.0))));
        const g = @min(255, @as(u8, @intFromFloat(255.0 * (context.fps / 60.0))));
        fps_color = Color.fromRgb(r, g, 0);
    }

    canvas.addText(@intCast(canvas.width - 30), 2, real_fps_text, fps_color, bg_color) catch {};

    context.frame_count += 1;

    return true;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var canvas = try terminal.TerminalCanvas.initAutoSize(allocator);
    defer canvas.deinit();

    canvas.setRefreshLimit(120);

    var animation_context = AnimationContext{
        .canvas = &canvas,
        .last_time = time.nanoTimestamp(),
    };

    try event.runEventLoop(&canvas, AnimationContext, &animation_context, animationCallback);
}
