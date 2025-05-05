const std = @import("std");
const io = std.io;
const fs = std.fs;
const process = std.process;
const mem = std.mem;
const TextWidget = @import("widgets/text.zig").TextWidget;
const TextListWidget = @import("widgets/text-list.zig").TextListWidget;
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
        "Item 1",
        "Item 2",
        "Item 3",
        "Item 4",
        "Item 5",
        "Item 6",
        "Item 7",
    };

    var list_widget = TextListWidget.init(&items, 0, 0, 50, 100);
    list_widget.setSelectedIndex(0);

    try list_widget.render(stdout);

    try stdout.print("\x1B[{d};1H", .{20});

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
            else => {},
        }
    }

    try stdout.writeAll("\x1B[2J\x1B[H");
}
