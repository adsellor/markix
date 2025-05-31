const std = @import("std");
const terminal = @import("backend/terminal/TerminalCanvas.zig");
const event = @import("utils/event.zig");
const terminal_utils = @import("utils/terminal.zig");
const Color = @import("layout/Color.zig").Color;
const Box = @import("layout/Box.zig").Box;
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
    root_box: *Box,
    last_canvas_width: u32 = 0,
    last_canvas_height: u32 = 0,
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

    if (context.last_canvas_width != canvas.width or context.last_canvas_height != canvas.height) {
        context.last_canvas_width = canvas.width;
        context.last_canvas_height = canvas.height;

        const outer_width: u16 = @min(60, canvas.width / 2);
        const outer_height: u16 = @min(20, canvas.height / 4);
        const outer_x: u16 = @intCast((canvas.width - outer_width) / 2);
        const outer_y: u16 = @intCast((canvas.height / 4 - outer_height) / 2);

        context.root_box.width = outer_width;
        context.root_box.height = outer_height;
        context.root_box.x = outer_x;
        context.root_box.y = outer_y;

        if (context.root_box.children.items.len > 0) {
            const inner_box = context.root_box.children.items[0];
            inner_box.width = if (outer_width > 10) outer_width - 10 else outer_width;
            inner_box.height = if (outer_height > 6) outer_height - 6 else outer_height;
        }
    }

    for (0..canvas.width) |x| {
        for (0..canvas.height) |y| {
            canvas.setPixel(@intCast(x), @intCast(y), bg_color);
        }
    }

    context.root_box.updatePositions();
    context.root_box.render(canvas);

    const wave_y = (canvas.height * 3) / 4;
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

    canvas.addText(10, 1, "Cool, init?", white, bg_color) catch {};
    canvas.addText(10, 2, "Press 'q' to quit", white, bg_color) catch {};

    var fps_buf: [40]u8 = undefined;
    const target_fps_text = std.fmt.bufPrint(&fps_buf, "Target FPS: {d}", .{240}) catch return true;
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
    canvas.setRefreshLimit(240);

    const blue = Color.fromRgb(50, 100, 200);
    const red = Color.fromRgb(200, 50, 50);

    const outer_width: u16 = @min(60, canvas.width / 2);
    const outer_height: u16 = @min(20, canvas.height / 4);
    const outer_x: u16 = @intCast((canvas.width - outer_width) / 2);
    const outer_y: u16 = @intCast((canvas.height / 4 - outer_height) / 2);

    const outer_box = try Box.init(allocator, outer_width, outer_height, outer_x, outer_y, blue);
    defer outer_box.deinit();

    const inner_width: u16 = outer_width - 10;
    const inner_height: u16 = outer_height - 6;
    const inner_box = try Box.init(allocator, inner_width, inner_height, 0, 0, red);

    try outer_box.addChild(inner_box);

    var animation_context = AnimationContext{
        .canvas = &canvas,
        .last_time = time.nanoTimestamp(),
        .root_box = outer_box,
        .last_canvas_width = canvas.width,
        .last_canvas_height = canvas.height,
    };

    try event.runEventLoop(&canvas, AnimationContext, &animation_context, animationCallback);
}
