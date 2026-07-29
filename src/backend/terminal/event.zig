const std = @import("std");
const input = @import("input.zig");
const limits = @import("limits.zig");
const terminal = @import("terminal.zig");
const TerminalCanvas = @import("canvas.zig").TerminalCanvas;

const posix = std.posix;

pub const Event = union(enum) {
    key: input.Key,
    resize: terminal.TerminalSize,
    poll: void,
    frame: void,
};

pub const LoopAction = enum { wait, redraw, stop };

pub const LoopOptions = struct {
    continuous_frames: bool = false,
    resize_poll_ms: u16 = 50,
};

pub fn read_input() !input.Batch {
    var bytes: [limits.input_keys_max]u8 = undefined;
    const count = try posix.read(posix.STDIN_FILENO, &bytes);
    if (count > 0) return input.parse(bytes[0..count]);
    if (count == 0) return error.EndOfInput;
    unreachable;
}

pub fn run_event_loop(
    io: std.Io,
    canvas: *TerminalCanvas,
    options: LoopOptions,
    comptime Context: type,
    context: *Context,
    comptime callback: fn (*Context, Event) anyerror!LoopAction,
) !void {
    if (options.resize_poll_ms == 0) return error.InvalidResizePollPeriod;
    const original_terminal = try terminal.enable_raw_mode();
    defer terminal.disable_raw_mode(original_terminal) catch |err| {
        std.log.err("failed to restore terminal mode: {s}", .{@errorName(err)});
    };

    try TerminalCanvas.enter_alternate_screen(io);
    defer TerminalCanvas.exit_alternate_screen(io) catch |err| {
        std.log.err("failed to exit alternate screen: {s}", .{@errorName(err)});
    };

    if (try callback(context, .{ .frame = {} }) == .stop) return;
    try canvas.render(io);
    var running = true;
    while (running) {
        const previous_width = canvas.width;
        const previous_height = canvas.height;
        if (canvas.resizable) {
            const resize_action = try resize_if_needed(canvas, context, callback);
            if (resize_action == .stop) break;
        }
        const resized = previous_width != canvas.width or
            previous_height != canvas.height;
        if (resized) {
            running = try redraw(canvas, io, context, callback);
            continue;
        }
        const timeout_ms = if (options.continuous_frames)
            canvas.frame_timeout_ms()
        else
            @as(i32, options.resize_poll_ms);
        var action: LoopAction = .wait;
        if (try input_ready(timeout_ms)) {
            const batch = try read_input();
            for (batch.items()) |key| {
                const next_action = try dispatch_input(
                    canvas,
                    io,
                    context,
                    callback,
                    key,
                );
                action = merge_actions(action, next_action);
                if (action == .stop) break;
            }
            if (action == .wait) action = .redraw;
        } else {
            const canvas_changed = try canvas.poll_background(io);
            action = try callback(context, .{ .poll = {} });
            if (canvas_changed) action = merge_actions(action, .redraw);
        }
        if (action == .stop) break;
        if (action == .redraw or options.continuous_frames) {
            running = try redraw(canvas, io, context, callback);
        }
    }
}

fn dispatch_input(
    canvas: *TerminalCanvas,
    io: std.Io,
    context: anytype,
    comptime callback: anytype,
    key: input.Key,
) !LoopAction {
    return switch (key) {
        .pointer => |pointer| dispatch_pointer(
            canvas,
            io,
            context,
            callback,
            key,
            pointer,
        ),
        else => callback(context, .{ .key = key }),
    };
}

fn dispatch_pointer(
    canvas: *TerminalCanvas,
    io: std.Io,
    context: anytype,
    comptime callback: anytype,
    key: input.Key,
    pointer: input.Pointer,
) !LoopAction {
    var action: LoopAction = switch (canvas.handle_pointer(pointer)) {
        .ignored => .wait,
        .redraw => .redraw,
        .copy => copy: {
            try canvas.copy_selection(io);
            break :copy .redraw;
        },
    };
    if (pointer.action == .press) {
        const app_action = try callback(context, .{ .key = key });
        action = merge_actions(action, app_action);
    }
    return action;
}

fn merge_actions(current: LoopAction, next: LoopAction) LoopAction {
    if (current == .stop or next == .stop) return .stop;
    if (current == .redraw or next == .redraw) return .redraw;
    return .wait;
}

fn resize_if_needed(
    canvas: *TerminalCanvas,
    context: anytype,
    comptime callback: anytype,
) !LoopAction {
    const size = try terminal.get_terminal_size();
    const canvas_height = std.math.mul(u16, size.height, 2) catch
        return error.CanvasTooTall;
    if (size.width != canvas.width or canvas_height != canvas.height) {
        try canvas.resize(size.width, canvas_height);
        return callback(context, .{ .resize = size });
    }
    return .wait;
}

fn redraw(
    canvas: *TerminalCanvas,
    io: std.Io,
    context: anytype,
    comptime callback: anytype,
) !bool {
    if (try callback(context, .{ .frame = {} }) == .stop) return false;
    try canvas.render(io);
    return true;
}

fn input_ready(timeout_ms: i32) !bool {
    std.debug.assert(timeout_ms > 0);
    var descriptors = [_]posix.pollfd{.{
        .fd = posix.STDIN_FILENO,
        .events = posix.POLL.IN,
        .revents = 0,
    }};
    const ready_count = try posix.poll(&descriptors, timeout_ms);
    if (ready_count == 0) return false;
    const events = descriptors[0].revents;
    if (events & posix.POLL.NVAL != 0) return error.InvalidInputDescriptor;
    if (events & posix.POLL.ERR != 0) return error.InputError;
    if (events & posix.POLL.HUP != 0) return error.EndOfInput;
    return events & posix.POLL.IN != 0;
}
