const std = @import("std");
const builtin = @import("builtin");

const Color = @import("Color.zig").Color;
const Patch = @import("Patch.zig").Patch;
const TextLayer = @import("TextLayer.zig").TextLayer;

const terminal_utils = @import("../utils/terminal.zig");

const mem = std.mem;
const Allocator = mem.Allocator;
const io = std.io;
const time = std.time;
const posix = std.posix;

pub const TerminalCanvas = struct {
    width: u32,
    height: u32,
    buffer: []Color,
    previous_buffer: []Color,
    allocator: Allocator,
    resizable: bool = false,
    frame_limit_nanos: u64,
    last_frame_time: i128,
    last_loop_width: u32 = 0,
    last_loop_height: u32 = 0,
    text_layer: TextLayer,
    render_mode: enum { PixelsOnly, TextOnly, Combined } = .Combined,

    pub fn init(allocator: Allocator, width: u32, height: u32) !TerminalCanvas {
        const buffer = try allocator.alloc(Color, width * height);
        const previous_buffer = try allocator.alloc(Color, width * height);

        @memset(buffer, Color.fromRgb(0, 0, 0));
        @memset(previous_buffer, Color.fromRgba(0, 0, 0, 0));

        return TerminalCanvas{
            .width = width,
            .height = height,
            .buffer = buffer,
            .previous_buffer = previous_buffer,
            .allocator = allocator,
            .frame_limit_nanos = 1_000_000_000 / 120,
            .last_frame_time = time.nanoTimestamp(),
            .text_layer = TextLayer.init(allocator),
        };
    }

    pub fn initAutoSize(allocator: Allocator) !TerminalCanvas {
        const size = try getTerminalSize();
        var canvas = try TerminalCanvas.init(allocator, size.width, size.height * 2);
        canvas.resizable = true;
        return canvas;
    }

    pub fn deinit(self: *TerminalCanvas) void {
        self.text_layer.deinit();
        self.allocator.free(self.buffer);
        self.allocator.free(self.previous_buffer);
    }

    pub fn setRefreshLimit(self: *TerminalCanvas, fps: u32) void {
        self.frame_limit_nanos = 1_000_000_000 / @as(u64, fps);
    }

    pub fn setPixel(self: *TerminalCanvas, x: u32, y: u32, color: Color) void {
        if (x >= self.width or y >= self.height) return;
        const index = y * self.width + x;
        self.buffer[index] = color;
    }

    pub fn getPixel(self: *const TerminalCanvas, x: u32, y: u32) Color {
        if (x >= self.width or y >= self.height) return Color.fromRgb(0, 0, 0);
        const index = y * self.width + x;
        return self.buffer[index];
    }

    pub fn filledRect(self: *TerminalCanvas, x: u32, y: u32, width: u32, height: u32, color: Color) void {
        const end_x = @min(x + width, self.width);
        const end_y = @min(y + height, self.height);

        var py: u32 = y;
        while (py < end_y) : (py += 1) {
            var px: u32 = x;
            while (px < end_x) : (px += 1) {
                self.setPixel(px, py, color);
            }
        }
    }

    fn calculatePatches(self: *const TerminalCanvas) !std.ArrayList(Patch) {
        var patches = std.ArrayList(Patch).init(self.allocator);
        var active_patch: ?Patch = null;

        var y: usize = 0;
        while (y < self.height) : (y += 2) {
            var x: usize = 0;
            while (x < self.width) : (x += 1) {
                const y1 = self.buffer[y * self.width + x];
                const y2 = if (y + 1 >= self.height)
                    Color.fromRgb(0, 0, 0)
                else
                    self.buffer[(y + 1) * self.width + x];

                const py1 = self.previous_buffer[y * self.width + x];
                const py2 = if (y + 1 >= self.height)
                    Color.fromRgb(0, 0, 0)
                else
                    self.previous_buffer[(y + 1) * self.width + x];

                if (!y1.equals(py1) or !y2.equals(py2)) {
                    if (active_patch == null) {
                        active_patch = Patch.init(self.allocator, @intCast(x), @intCast(y / 2));
                    }

                    try active_patch.?.addTwoRowPixel(y1, y2);
                } else if (active_patch != null) {
                    try patches.append(active_patch.?);
                    active_patch = null;
                }
            }

            if (active_patch != null) {
                try patches.append(active_patch.?);
                active_patch = null;
            }
        }

        if (active_patch != null) {
            try patches.append(active_patch.?);
        }

        return patches;
    }

    fn elapsedSinceLastFrame(self: *const TerminalCanvas) u64 {
        const now = time.nanoTimestamp();
        const elapsed = @as(u64, @intCast(now - self.last_frame_time));
        return elapsed;
    }

    fn waitForNextFrame(self: *TerminalCanvas) void {
        const elapsed = self.elapsedSinceLastFrame();

        if (elapsed < self.frame_limit_nanos) {
            const wait_time = self.frame_limit_nanos - elapsed;

            if (wait_time / 2 > 1_000_000) {
                time.sleep(wait_time / 2);
            }

            const target_time = time.nanoTimestamp() + @as(i64, @intCast(wait_time - wait_time / 2));
            while (time.nanoTimestamp() < target_time) {
                std.atomic.spinLoopHint();
            }
        }

        self.last_frame_time = time.nanoTimestamp();
    }

    pub fn resize(self: *TerminalCanvas, width: u32, height: u32) !void {
        if (width == self.width and height == self.height) return;

        const new_buffer = try self.allocator.alloc(Color, width * height);
        const new_previous = try self.allocator.alloc(Color, width * height);

        @memset(new_buffer, Color.fromRgb(0, 0, 0));
        @memset(new_previous, Color.fromRgba(0, 0, 0, 0));

        const copy_width = @min(width, self.width);
        const copy_height = @min(height, self.height);

        var y: u32 = 0;
        while (y < copy_height) : (y += 1) {
            var x: u32 = 0;
            while (x < copy_width) : (x += 1) {
                new_buffer[y * width + x] = self.buffer[y * self.width + x];
            }
        }

        self.allocator.free(self.buffer);
        self.allocator.free(self.previous_buffer);

        self.buffer = new_buffer;
        self.previous_buffer = new_previous;
        self.width = width;
        self.height = height;
    }

    pub fn clearText(self: *TerminalCanvas) void {
        self.text_layer.clear();
    }

    pub fn addText(self: *TerminalCanvas, x: u16, y: u16, text: []const u8, fg: Color, bg: ?Color) !void {
        try self.text_layer.addText(x, y, text, fg, bg);
    }

    pub fn render(self: *TerminalCanvas) !void {
        self.waitForNextFrame();

        var stdout = std.io.getStdOut();
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        var buffered_writer = buffer.writer();

        if (self.render_mode != .TextOnly) {
            buffered_writer.writeAll("\x1B[?25l") catch {};

            const patches = try self.calculatePatches();
            for (patches.items) |patch| {
                try patch.apply(buffered_writer);
            }
        }

        if (self.render_mode != .PixelsOnly) {
            try self.text_layer.render(buffered_writer);
        }

        try buffered_writer.print("\x1B[{d};{d}H\x1B[?25h", .{ self.height / 2 + 1, self.width + 1 });

        try stdout.writeAll(buffer.items);
        @memcpy(self.previous_buffer, self.buffer);
    }

    pub fn clear(self: *TerminalCanvas) void {
        @memset(self.buffer, Color.fromRgb(0, 0, 0));
    }

    pub fn enterAlternateScreen() !void {
        const stdout = io.getStdOut().writer();
        try stdout.writeAll("\x1B[?1049h");
    }

    pub fn exitAlternateScreen() !void {
        const stdout = io.getStdOut().writer();
        try stdout.writeAll("\x1B[?1049l");
    }
};

pub const TerminalSize = struct {
    width: u32,
    height: u32,
};

pub fn getTerminalSize() !TerminalSize {
    const STDOUT_FILENO = 1;
    const winsize = extern struct {
        ws_row: u16,
        ws_col: u16,
        ws_xpixel: u16,
        ws_ypixel: u16,
    };
    var ws: winsize = undefined;

    const TIOCGWINSZ: u32 = switch (builtin.os.tag) {
        .linux => 0x5413,
        .macos, .freebsd, .netbsd, .openbsd, .dragonfly => 0x40087468,
        else => @compileError("Unsupported OS"),
    };

    const result = posix.system.ioctl(STDOUT_FILENO, TIOCGWINSZ, @intFromPtr(&ws));
    if (result < 0) {
        return error.TerminalSizeQueryFailed;
    }

    return TerminalSize{
        .width = @as(u32, ws.ws_col),
        .height = @as(u32, ws.ws_row),
    };
}

pub const EventType = enum {
    Key,
    Resize,
    Unknown,
};

pub const Event = union(EventType) {
    Key: u8,
    Resize: TerminalSize,
    Unknown: void,
};

pub fn readEvent(reader: anytype) !Event {
    var buf: [16]u8 = undefined;

    const bytes_read = try reader.read(buf[0..1]);
    if (bytes_read == 0) return Event.Unknown;

    if (buf[0] == 0x1B) {
        const more_bytes = try reader.read(buf[1..3]);
        if (more_bytes == 0) return Event{ .Key = buf[0] };

        // TODO: Read for resize and adjust accordingly
        // Will think about it when I finalize the layout engine
        // For now just return the escape key
        return Event{ .Key = buf[0] };
    }

    return Event{ .Key = buf[0] };
}

pub fn runEventLoop(canvas: *TerminalCanvas, comptime ContextType: type, context: *ContextType, comptime callback: fn (*ContextType, Event) bool) !void {
    const stdin = io.getStdIn().reader();
    const original_termios = try terminal_utils.enableRawMode();
    defer terminal_utils.disableRawMode(original_termios) catch {};

    try canvas.enterAlternateScreen();
    defer canvas.exitAlternateScreen() catch {};

    canvas.last_loop_width = canvas.width;
    canvas.last_loop_height = canvas.height;

    while (true) {
        if (canvas.resizable) {
            const term_size = try getTerminalSize();
            if (term_size.width != canvas.width or term_size.height * 2 != canvas.height) {
                try canvas.resize(term_size.width, term_size.height * 2);
                _ = callback(context, Event{ .Resize = term_size });
            }
        }

        var pollfds = [_]posix.pollfd{
            .{ .fd = 0, .events = posix.POLL.IN, .revents = 0 },
        };

        const poll_result = posix.poll(&pollfds, 0);

        if (poll_result > 0 and (pollfds[0].revents & posix.POLL.IN) != 0) {
            const event = try readEvent(stdin);
            const should_continue = callback(context, event);
            if (!should_continue) break;
        }

        try canvas.render();
    }
}
