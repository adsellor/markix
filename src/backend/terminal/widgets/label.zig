const Surface = @import("../surface.zig").Surface;
const Rect = @import("../../../framework/layout/rect.zig").Rect;
const Style = @import("../../../framework/style.zig").Style;

pub const Label = struct {
    text: []const u8,
    style: Style,
    muted: bool = false,

    pub fn draw(self: Label, surface: Surface, rect: Rect) !void {
        if (rect.width == 0 or rect.height == 0) return;
        const foreground = if (self.muted) self.style.muted else self.style.foreground;
        try surface.text_in(rect, 0, self.text, foreground, self.style.background);
    }
};
