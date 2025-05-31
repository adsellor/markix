const std = @import("std");
const io = std.io;
const terminal_utils = @import("terminal.zig");
const TerminalSize = @import("terminal.zig").TerminalSize;
const TerminalCanvas = @import("../backend/terminal/TerminalCanvas.zig").TerminalCanvas;
const posix = std.posix;

pub const EventType = enum {
    Key,
    Resize,
    Unknown,
    Frame,
};

pub const Event = union(EventType) {
    Key: u8,
    Resize: TerminalSize,
    Unknown: void,
    Frame: void,
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

pub fn runEventLoop(
    canvas: *TerminalCanvas,
    comptime ContextType: type,
    context: *ContextType,
    comptime callback: fn (*ContextType, Event) bool,
) !void {
    const stdin = io.getStdIn().reader();

    const original_termios = try terminal_utils.enableRawMode();
    defer terminal_utils.disableRawMode(original_termios) catch {};

    try TerminalCanvas.enterAlternateScreen();
    defer TerminalCanvas.exitAlternateScreen() catch {};

    canvas.last_loop_width = canvas.width;
    canvas.last_loop_height = canvas.height;

    while (true) {
        if (canvas.resizable) {
            const term_size = try terminal_utils.getTerminalSize();
            if (term_size.width != canvas.width or term_size.height * 2 != canvas.height) {
                try canvas.resize(term_size.width, term_size.height * 2);
                _ = callback(context, Event{ .Resize = term_size });
            }
        }

        var pollfds = [_]posix.pollfd{
            .{ .fd = 0, .events = posix.POLL.IN, .revents = 0 },
        };
        const poll_result = try posix.poll(&pollfds, 0);
        if (poll_result > 0 and (pollfds[0].revents & posix.POLL.IN) != 0) {
            const e = try readEvent(stdin);
            const should_continue = callback(context, e);
            if (!should_continue) break;
        }

        // NOTE: This is a dummy event
        // We will use proper callback and event handling later
        // Maybe this can be tied to signals implementation idk
        const should_continue = callback(context, Event{ .Frame = {} });
        if (!should_continue) break;

        try canvas.render();
    }
}
