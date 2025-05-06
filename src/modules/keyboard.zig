const std = @import("std");
const posix = std.posix;
const builtin = @import("builtin");

pub fn enableRawMode() !posix.termios {
    const STDIN_FILENO = 0;

    const original_termios = try posix.tcgetattr(STDIN_FILENO);
    var termios = original_termios;

    termios.lflag.ECHO = false;
    termios.lflag.ICANON = false;
    termios.lflag.ISIG = false;
    termios.lflag.IEXTEN = false;

    termios.iflag.IXON = false;
    termios.iflag.ICRNL = false;
    termios.iflag.BRKINT = false;
    termios.iflag.INPCK = false;
    termios.iflag.ISTRIP = false;
    termios.oflag.OPOST = false;
    termios.cflag.CSIZE = .CS8;

    termios.cc[@intFromEnum(posix.V.MIN)] = 1;
    termios.cc[@intFromEnum(posix.V.TIME)] = 0;

    try posix.tcsetattr(STDIN_FILENO, .FLUSH, termios);

    return original_termios;
}

pub fn disableRawMode(original_termios: posix.termios) !void {
    const STDIN_FILENO = 0;
    try posix.tcsetattr(STDIN_FILENO, .FLUSH, original_termios);
}

pub fn readKey(reader: anytype) !u8 {
    var buffer: [1]u8 = undefined;
    _ = try reader.read(&buffer);
    return buffer[0];
}
