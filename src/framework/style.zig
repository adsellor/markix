const Color = @import("layout/color.zig").Color;

pub const Style = struct {
    foreground: Color,
    background: Color,
    muted: Color,
    accent: Color,
    border: Color,
    selected_foreground: Color,
    selected_background: Color,

    pub fn monochrome(foreground: Color, background: Color) Style {
        return .{
            .foreground = foreground,
            .background = background,
            .muted = foreground,
            .accent = foreground,
            .border = foreground,
            .selected_foreground = background,
            .selected_background = foreground,
        };
    }
};

pub const TextSelectionStyle = struct {
    foreground: Color,
    background: Color,
    active_background: Color,
    anchor_background: Color,
    cursor_foreground: Color,
    cursor_background: Color,
};
