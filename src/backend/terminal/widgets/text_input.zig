const Surface = @import("../surface.zig").Surface;
const Rect = @import("../../../framework/layout/rect.zig").Rect;
const Style = @import("../../../framework/style.zig").Style;
const Attributes = @import("../text_style.zig").Attributes;

pub const Options = struct {
    prompt: []const u8 = "",
    placeholder: []const u8 = "",
    style: Style,
    focused: bool,
    prompt_attributes: Attributes = .{ .bold = true },
    value_attributes: Attributes = .{},
    placeholder_attributes: Attributes = .{ .dim = true },
    cursor_attributes: Attributes = .{ .bold = true },
};

pub fn draw(
    input: anytype,
    surface: Surface,
    rect: Rect,
    options: Options,
) !void {
    if (rect.width == 0 or rect.height == 0) return;
    surface.fill(Rect.init(rect.x, rect.y, rect.width, 1), options.style.background);
    const prompt_length: u16 = @intCast(@min(options.prompt.len, rect.width));
    if (prompt_length > 0) {
        try surface.styled_text(
            rect.x,
            rect.y,
            options.prompt[0..prompt_length],
            .{
                .foreground = options.style.accent,
                .background = options.style.background,
                .attributes = options.prompt_attributes,
            },
        );
    }
    if (prompt_length >= rect.width) return;
    const value_rect = Rect.init(
        rect.x + prompt_length,
        rect.y,
        rect.width - prompt_length,
        1,
    );
    if (options.focused) {
        try draw_focused(input, surface, value_rect, options);
    } else {
        try draw_idle(input, surface, value_rect, options);
    }
}

fn draw_idle(
    input: anytype,
    surface: Surface,
    rect: Rect,
    options: Options,
) !void {
    const value = input.value();
    const text = if (value.len == 0) options.placeholder else value;
    const foreground = if (value.len == 0)
        options.style.muted
    else
        options.style.foreground;
    try surface.styled_text_in(rect, 0, text, .{
        .foreground = foreground,
        .background = options.style.background,
        .attributes = if (value.len == 0)
            options.placeholder_attributes
        else
            options.value_attributes,
    });
}

fn draw_focused(
    input: anytype,
    surface: Surface,
    rect: Rect,
    options: Options,
) !void {
    const value = input.value();
    const visible_length: u16 = @intCast(@min(value.len, rect.width));
    const cursor: u16 = @min(input.cursor, @min(visible_length, rect.width - 1));
    if (cursor > 0) {
        try surface.styled_text(
            rect.x,
            rect.y,
            value[0..cursor],
            .{
                .foreground = options.style.foreground,
                .background = options.style.background,
                .attributes = options.value_attributes,
            },
        );
    }
    const cursor_byte = if (cursor < visible_length) value[cursor] else ' ';
    try surface.styled_text(
        rect.x + cursor,
        rect.y,
        &.{cursor_byte},
        .{
            .foreground = options.style.selected_foreground,
            .background = options.style.selected_background,
            .attributes = options.cursor_attributes,
        },
    );
    if (cursor + 1 < visible_length) {
        try surface.styled_text(
            rect.x + cursor + 1,
            rect.y,
            value[cursor + 1 .. visible_length],
            .{
                .foreground = options.style.foreground,
                .background = options.style.background,
                .attributes = options.value_attributes,
            },
        );
    }
}

test "focused text input emits an independently patchable cursor cell" {
    const std = @import("std");
    const Canvas = @import("../canvas.zig").TerminalCanvas;
    const Color = @import("../../../framework/layout/color.zig").Color;
    const TextInput = @import("../../../framework/widgets/text_input.zig").TextInput;
    var canvas = try Canvas.init(std.testing.allocator, 20, 4);
    defer canvas.deinit();
    var input = TextInput(8){};
    try input.set("abc");
    _ = try input.handle(.left);
    _ = try input.handle(.left);
    const foreground = Color.from_rgb(230, 230, 230);
    const background = Color.from_rgb(20, 20, 20);
    const style = Style.monochrome(foreground, background);
    try draw(&input, .{ .canvas = &canvas }, Rect.init(1, 1, 10, 1), .{
        .style = style,
        .focused = true,
    });
    try std.testing.expectEqual(@as(usize, 3), canvas.text_entries.items.len);
    const cursor = &canvas.text_entries.items[1];
    try std.testing.expectEqual(@as(u16, 2), cursor.x);
    try std.testing.expectEqualStrings("b", cursor.bytes());
    try std.testing.expect(cursor.background_color.?.equals(foreground));
}
