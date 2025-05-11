const std = @import("std");
const builtin = @import("builtin");

const Color = @import("Color.zig").Color;
const Patch = @import("Patch.zig").Patch;
const TextEntry = @import("TextEntry.zig").TextEntry;

const terminal_utils = @import("../utils/terminal.zig");

const mem = std.mem;
const Allocator = mem.Allocator;
const io = std.io;
const time = std.time;

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
    text_entries: std.ArrayList(TextEntry),
    previous_text_entries: std.ArrayList(TextEntry),

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
            .text_entries = std.ArrayList(TextEntry).init(allocator),
            .previous_text_entries = std.ArrayList(TextEntry).init(allocator),
        };
    }

    pub fn initAutoSize(allocator: Allocator) !TerminalCanvas {
        const size = try terminal_utils.getTerminalSize();
        var canvas = try TerminalCanvas.init(allocator, size.width, size.height * 2);
        canvas.resizable = true;
        return canvas;
    }

    pub fn deinit(self: *TerminalCanvas) void {
        for (self.text_entries.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.text_entries.deinit();

        for (self.previous_text_entries.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.previous_text_entries.deinit();

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

    pub fn addText(self: *TerminalCanvas, x: u32, y: u32, text: []const u8, fg: Color, bg: ?Color) !void {
        const text_copy = try self.allocator.alloc(u8, text.len);
        @memcpy(text_copy, text);

        try self.text_entries.append(TextEntry{
            .x = x,
            .y = y,
            .text = text_copy,
            .foreground_color = fg,
            .background_color = bg,
        });
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

        var previous_text_positions = std.AutoHashMap(u64, usize).init(self.allocator);
        defer previous_text_positions.deinit();

        for (self.previous_text_entries.items, 0..) |entry, i| {
            const position_key = (@as(u64, entry.y) << 32) | entry.x;
            try previous_text_positions.put(position_key, i);
        }

        for (self.text_entries.items) |entry| {
            const position_key = (@as(u64, entry.y) << 32) | entry.x;

            var changed = true;
            if (previous_text_positions.get(position_key)) |prev_idx| {
                const prev_entry = &self.previous_text_entries.items[prev_idx];
                if (entry.equals(prev_entry)) {
                    changed = false;
                }
                _ = previous_text_positions.remove(position_key);
            }

            if (changed) {
                const text_patch = try Patch.initForText(self.allocator, @intCast(entry.x), @intCast(entry.y), entry.text, entry.foreground_color, entry.background_color);
                try patches.append(text_patch);
            }
        }

        var it = previous_text_positions.iterator();
        while (it.next()) |kv| {
            const prev_idx = kv.value_ptr.*;
            const entry = &self.previous_text_entries.items[prev_idx];

            const clear_text = try self.allocator.alloc(u8, entry.text.len);
            defer self.allocator.free(clear_text);
            @memset(clear_text, ' ');

            const clear_patch = try Patch.initForText(
                self.allocator,
                @intCast(entry.x),
                @intCast(entry.y),
                clear_text,
                Color.fromRgb(0, 0, 0),
                Color.fromRgb(0, 0, 0),
            );

            try patches.append(clear_patch);
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

    pub fn render(self: *TerminalCanvas) !void {
        self.waitForNextFrame();

        var stdout = std.io.getStdOut();
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        var buffered_writer = buffer.writer();

        buffered_writer.writeAll("\x1B[?25l") catch {};

        const patches = try self.calculatePatches();
        for (patches.items) |patch| {
            try patch.apply(buffered_writer);
        }
        defer {
            for (patches.items) |*patch| {
                patch.deinit();
            }
            patches.deinit();
        }

        try buffered_writer.print("\x1B[{d};{d}H\x1B[?25h", .{ self.height / 2 + 1, self.width + 1 });

        try stdout.writeAll(buffer.items);

        @memcpy(self.previous_buffer, self.buffer);
        for (self.previous_text_entries.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.previous_text_entries.clearRetainingCapacity();

        for (self.text_entries.items) |*entry| {
            const cloned_entry = try entry.clone(self.allocator);
            try self.previous_text_entries.append(cloned_entry);
        }

        for (self.text_entries.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.text_entries.clearRetainingCapacity();
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
