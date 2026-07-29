const Color = @import("../../../framework/layout/color.zig").Color;
const Rect = @import("../../../framework/layout/rect.zig").Rect;
const Surface = @import("../surface.zig").Surface;
const Attributes = @import("../text_style.zig").Attributes;

pub const BadgeStyle = struct {
    foreground: Color,
    background: Color,
    attributes: Attributes = .{ .bold = true },
    padding: u8 = 1,
};

pub const Badge = struct {
    style: BadgeStyle,

    pub fn draw(
        self: Badge,
        surface: Surface,
        rect: Rect,
        text: []const u8,
    ) !u16 {
        if (rect.width == 0 or rect.height == 0) return 0;
        const padding = @min(@as(u16, self.style.padding), rect.width);
        const text_width = rect.width -| padding *| 2;
        const length: u16 = @intCast(@min(text.len, text_width));
        const width = @min(rect.width, length + padding *| 2);
        surface.fill(Rect.init(rect.x, rect.y, width, 1), self.style.background);
        if (length > 0) {
            try surface.styled_text(
                rect.x + padding,
                rect.y,
                text[0..length],
                .{
                    .foreground = self.style.foreground,
                    .background = self.style.background,
                    .attributes = self.style.attributes,
                },
            );
        }
        return width;
    }
};
