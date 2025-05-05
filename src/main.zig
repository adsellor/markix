const std = @import("std");
const io = std.io;
const fs = std.fs;
const process = std.process;
const mem = std.mem;
const TextWidget = @import("widgets/text.zig").TextWidget;
const TextListWidget = @import("widgets/text-list.zig").TextListWidget;
const ScrollView = @import("widgets/scroll-view.zig").ScrollView;
const KeyHandler = @import("widgets/keyboard.zig").KeyHandler;

pub fn main() !void {
    const original_termios = try KeyHandler.enableRawMode();
    defer KeyHandler.disableRawMode(original_termios) catch {};

    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.writer();

    try stdout.writeAll("\x1B[2J\x1B[H");

    const items = [_][]const u8{
        "Item 1",
        "Item 2",
        "Item 3",
        "Item 4",
        "Item 5",
        "Item 6",
        "Item 7",
        "Item 8",
        "Item 9",
        "Item 10",
        "Item 11",
        "Item 12",
        "Item 13",
        "Item 14",
    };

    const visible_height = 5;
    const list_width = 50;

    var scroll_view = ScrollView.init(0, 0, list_width, visible_height, items.len);

    var list_widget = TextListWidget.init(&items, 0, 0, list_width, visible_height);
    list_widget.setSelectedIndex(0);

    list_widget.setScrollView(&scroll_view);

    try list_widget.render(stdout);

    try stdout.print("\x1B[{d};1H", .{visible_height + 2});
    try stdout.writeAll("Use j/k to navigate, q to quit");

    const stdin = std.io.getStdIn();
    const stdin_reader = stdin.reader();

    while (true) {
        const key = try KeyHandler.readKey(stdin_reader);

        switch (key) {
            'q' => break,
            'j' => {
                list_widget.moveSelection(1);
                try list_widget.render(stdout);
            },
            'k' => {
                list_widget.moveSelection(-1);
                try list_widget.render(stdout);
            },
            'J' => {
                scroll_view.scrollDown();
                try list_widget.render(stdout);
            },
            'K' => {
                scroll_view.scrollUp();
                try list_widget.render(stdout);
            },
            else => {},
        }

        try stdout.print("\x1B[{d};1H", .{visible_height + 3});
    }

    try stdout.writeAll("\x1B[2J\x1B[H");
}
