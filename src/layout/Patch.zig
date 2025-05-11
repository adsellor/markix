const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Color = @import("Color.zig").Color;

pub const Patch = struct {
    x: u16,
    y: u16,
    data: std.ArrayList(u8),
    previous_colors: ?struct { upper: Color, lower: Color } = null,
    is_text: bool = false,

    pub fn init(allocator: Allocator, x: u16, y: u16) Patch {
        return .{
            .x = x,
            .y = y,
            .data = std.ArrayList(u8).init(allocator),
            .is_text = false,
        };
    }

    pub fn initForText(
        allocator: Allocator,
        x: u16,
        y: u16,
        text: []const u8,
        fg: Color,
        bg: ?Color,
    ) !Patch {
        var patch = Patch{
            .x = x,
            .y = y,
            .data = std.ArrayList(u8).init(allocator),
            .is_text = true,
        };

        var writer = patch.data.writer();

        try writer.print("\x1B[38;2;{d};{d};{d}m", .{ fg.r, fg.g, fg.b });

        if (bg) |background| {
            try writer.print("\x1B[48;2;{d};{d};{d}m", .{ background.r, background.g, background.b });
        }

        try patch.data.appendSlice(text);
        try patch.data.appendSlice("\x1B[0m");

        return patch;
    }

    pub fn deinit(self: *Patch) void {
        self.data.deinit();
    }

    pub fn apply(self: *const Patch, writer: anytype) !void {
        try writer.print("\x1B[{d};{d}H", .{ self.y + 1, self.x + 1 });
        try writer.writeAll(self.data.items);
    }

    pub fn addTwoRowPixel(self: *Patch, upper: Color, lower: Color) !void {
        const should_update_colors = self.previous_colors == null or
            !self.previous_colors.?.upper.equals(upper) or
            !self.previous_colors.?.lower.equals(lower);

        if (should_update_colors) {
            try self.data.writer().print("\x1B[38;2;{d};{d};{d}m", .{ upper.r, upper.g, upper.b });
            try self.data.writer().print("\x1B[48;2;{d};{d};{d}m", .{ lower.r, lower.g, lower.b });
            self.previous_colors = .{ .upper = upper, .lower = lower };
        }

        try self.data.writer().writeAll("▀");
    }
};
