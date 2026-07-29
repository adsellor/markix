const std = @import("std");
const xml = @import("xml.zig");

pub const block_count_max: u8 = 96;
pub const block_text_bytes_max: u16 = 1_536;
pub const block_url_bytes_max: u16 = 512;
pub const source_bytes_max: u16 = 32 * 1_024;

pub const Kind = enum {
    paragraph,
    heading,
    list_item,
    quote,
    code,
    link,
    image,
};

pub const Text = FixedText(block_text_bytes_max);
pub const Url = FixedText(block_url_bytes_max);

pub const Block = struct {
    kind: Kind,
    text: Text = .{},
    url: Url = .{},
};

pub const Document = struct {
    blocks: [block_count_max]Block = undefined,
    count: u8 = 0,

    pub fn first_image(self: *const Document) ?[]const u8 {
        var index: u8 = 0;
        while (index < self.count) : (index += 1) {
            const block = &self.blocks[index];
            if (block.kind == .image and !block.url.is_empty()) return block.url.bytes();
        }
        return null;
    }
};

pub fn parse(source: []const u8) Document {
    var decoded_buffer: [source_bytes_max]u8 = undefined;
    const decoded = decode_markup(source, &decoded_buffer);
    var document = Document{};
    parse_blocks(decoded, &document);
    if (document.count == 0) append_block(&document, .paragraph, decoded, "");
    return document;
}

pub fn copy_plain_text(source: []const u8, target: anytype) void {
    var decoded_buffer: [source_bytes_max]u8 = undefined;
    const decoded = decode_markup(source, &decoded_buffer);
    target.clear();
    append_plain(decoded, target);
}

pub fn write_plain(document: *const Document, target: anytype) void {
    target.clear();
    var index: u8 = 0;
    while (index < document.count) : (index += 1) {
        const text = document.blocks[index].text.bytes();
        if (text.len == 0) continue;
        append_separator(target);
        append_bytes(target, text);
    }
}

fn parse_blocks(source: []const u8, document: *Document) void {
    var cursor: usize = 0;
    while (cursor < source.len and document.count < block_count_max) {
        const start = std.mem.indexOfScalarPos(u8, source, cursor, '<') orelse break;
        const end = std.mem.indexOfScalarPos(u8, source, start, '>') orelse break;
        const tag = source[start .. end + 1];
        const name = tag_name(tag);
        if (std.ascii.eqlIgnoreCase(name, "img")) {
            append_image(document, tag);
            cursor = end + 1;
            continue;
        }
        const kind = block_kind(name) orelse {
            cursor = end + 1;
            continue;
        };
        const close = xml.find_close_tag(source, end + 1, name) orelse {
            cursor = end + 1;
            continue;
        };
        const inner = source[end + 1 .. close];
        append_block(document, kind, inner, link_url(tag, inner));
        append_images(document, inner);
        const close_end = std.mem.indexOfScalarPos(u8, source, close, '>') orelse break;
        cursor = close_end + 1;
    }
}

fn block_kind(name: []const u8) ?Kind {
    if (name.len == 2 and name[0] == 'h' and name[1] >= '1' and name[1] <= '6') {
        return .heading;
    }
    if (std.ascii.eqlIgnoreCase(name, "p")) return .paragraph;
    if (std.ascii.eqlIgnoreCase(name, "li")) return .list_item;
    if (std.ascii.eqlIgnoreCase(name, "blockquote")) return .quote;
    if (std.ascii.eqlIgnoreCase(name, "pre")) return .code;
    if (std.ascii.eqlIgnoreCase(name, "code")) return .code;
    if (std.ascii.eqlIgnoreCase(name, "a")) return .link;
    return null;
}

fn append_block(
    document: *Document,
    kind: Kind,
    source: []const u8,
    url: []const u8,
) void {
    if (document.count == block_count_max) return;
    var block = Block{ .kind = kind };
    copy_plain_text(source, &block.text);
    set_truncated(&block.url, url);
    if (block.text.is_empty() and block.url.is_empty()) return;
    document.blocks[document.count] = block;
    document.count += 1;
}

fn append_images(document: *Document, source: []const u8) void {
    var cursor: usize = 0;
    while (xml.find_open_tag(source, cursor, "img")) |start| {
        const end = std.mem.indexOfScalarPos(u8, source, start, '>') orelse return;
        append_image(document, source[start .. end + 1]);
        cursor = end + 1;
        if (document.count == block_count_max) return;
    }
}

fn append_image(document: *Document, tag: []const u8) void {
    const url = xml.attribute_value(tag, "src") orelse return;
    const alt = xml.attribute_value(tag, "alt") orelse "Image";
    append_block(document, .image, alt, url);
}

fn link_url(tag: []const u8, inner: []const u8) []const u8 {
    _ = inner;
    return xml.attribute_value(tag, "href") orelse "";
}

fn tag_name(tag: []const u8) []const u8 {
    if (tag.len < 2) return "";
    var start: usize = 1;
    if (tag[start] == '/') start += 1;
    const end = std.mem.indexOfAnyPos(u8, tag, start, " \t\r\n/>") orelse tag.len - 1;
    return tag[start..end];
}

fn decode_markup(source: []const u8, output: []u8) []const u8 {
    var source_index: usize = 0;
    var output_index: usize = 0;
    while (source_index < source.len and output_index < output.len) {
        if (std.mem.startsWith(u8, source[source_index..], "<![CDATA[")) {
            source_index += "<![CDATA[".len;
            continue;
        }
        if (std.mem.startsWith(u8, source[source_index..], "]]>")) {
            source_index += "]]>".len;
            continue;
        }
        if (decode_entity(source[source_index..])) |entity| {
            output[output_index] = entity.byte;
            output_index += 1;
            source_index += entity.consumed;
            continue;
        }
        output[output_index] = source[source_index];
        output_index += 1;
        source_index += 1;
    }
    return output[0..output_index];
}

fn append_plain(source: []const u8, target: anytype) void {
    var index: usize = 0;
    var space_pending = false;
    while (index < source.len and target.length < target.buffer.len) {
        if (source[index] == '<') {
            const end = std.mem.indexOfScalarPos(u8, source, index, '>') orelse break;
            space_pending = target.length > 0;
            index = end + 1;
            continue;
        }
        if (source[index] >= 0x80) {
            const sequence = std.unicode.utf8ByteSequenceLength(source[index]) catch 1;
            append_plain_byte(target, '?', &space_pending);
            index += @min(@as(usize, sequence), source.len - index);
            continue;
        }
        const entity = decode_entity(source[index..]);
        const byte = if (entity) |value| value.byte else source[index];
        const consumed = if (entity) |value| value.consumed else 1;
        append_plain_byte(target, byte, &space_pending);
        index += consumed;
    }
}

fn append_plain_byte(target: anytype, byte: u8, space_pending: *bool) void {
    if (std.ascii.isWhitespace(byte)) {
        space_pending.* = target.length > 0;
        return;
    }
    const punctuation = std.mem.containsAtLeast(u8, ".,;:!?)]}", 1, &.{byte});
    if (space_pending.* and !punctuation and target.length < target.buffer.len) {
        target.buffer[target.length] = ' ';
        target.length += 1;
    }
    if (target.length < target.buffer.len) {
        target.buffer[target.length] = byte;
        target.length += 1;
    }
    space_pending.* = false;
}

const Entity = struct {
    byte: u8,
    consumed: usize,
};

fn decode_entity(source: []const u8) ?Entity {
    const entities = [_]struct { encoded: []const u8, decoded: u8 }{
        .{ .encoded = "&amp;", .decoded = '&' },
        .{ .encoded = "&lt;", .decoded = '<' },
        .{ .encoded = "&gt;", .decoded = '>' },
        .{ .encoded = "&quot;", .decoded = '"' },
        .{ .encoded = "&#34;", .decoded = '"' },
        .{ .encoded = "&#39;", .decoded = '\'' },
        .{ .encoded = "&apos;", .decoded = '\'' },
        .{ .encoded = "&nbsp;", .decoded = ' ' },
        .{ .encoded = "&rsquo;", .decoded = '\'' },
        .{ .encoded = "&lsquo;", .decoded = '\'' },
        .{ .encoded = "&ldquo;", .decoded = '"' },
        .{ .encoded = "&rdquo;", .decoded = '"' },
        .{ .encoded = "&mdash;", .decoded = '-' },
        .{ .encoded = "&ndash;", .decoded = '-' },
    };
    for (entities) |entity| {
        if (std.mem.startsWith(u8, source, entity.encoded)) {
            return .{ .byte = entity.decoded, .consumed = entity.encoded.len };
        }
    }
    return decode_numeric_entity(source);
}

fn decode_numeric_entity(source: []const u8) ?Entity {
    if (!std.mem.startsWith(u8, source, "&#")) return null;
    const end = std.mem.indexOfScalar(u8, source, ';') orelse return null;
    if (end > 10) return null;
    const hexadecimal = source.len > 3 and (source[2] == 'x' or source[2] == 'X');
    const start: usize = if (hexadecimal) 3 else 2;
    const base: u8 = if (hexadecimal) 16 else 10;
    const value = std.fmt.parseInt(u21, source[start..end], base) catch return null;
    return .{
        .byte = if (value <= 127) @intCast(value) else '?',
        .consumed = end + 1,
    };
}

fn append_separator(target: anytype) void {
    if (target.length == 0) return;
    if (target.length == target.buffer.len) return;
    target.buffer[target.length] = ' ';
    target.length += 1;
}

fn append_bytes(target: anytype, value: []const u8) void {
    const available = target.buffer.len - target.length;
    const length = @min(value.len, available);
    @memcpy(target.buffer[target.length..][0..length], value[0..length]);
    target.length += @intCast(length);
}

fn set_truncated(target: anytype, value: []const u8) void {
    target.set(value[0..@min(value.len, target.buffer.len)]) catch unreachable;
}

fn FixedText(comptime capacity: u16) type {
    return struct {
        buffer: [capacity]u8 = undefined,
        length: u16 = 0,

        fn set(self: *@This(), value: []const u8) error{TextTooLong}!void {
            if (value.len > capacity) return error.TextTooLong;
            @memcpy(self.buffer[0..value.len], value);
            self.length = @intCast(value.len);
        }

        pub fn clear(self: *@This()) void {
            self.length = 0;
        }

        pub fn bytes(self: *const @This()) []const u8 {
            return self.buffer[0..self.length];
        }

        pub fn is_empty(self: *const @This()) bool {
            return self.length == 0;
        }
    };
}

test "document parser preserves styled blocks and images" {
    const source =
        \\&lt;h2&gt;A title&lt;/h2&gt;
        \\&lt;p&gt;A &amp;amp; B.&lt;img src="cover.png" alt="Cover"/&gt;&lt;/p&gt;
        \\&lt;blockquote&gt;Quoted&lt;/blockquote&gt;
    ;
    const document = parse(source);
    try std.testing.expectEqual(Kind.heading, document.blocks[0].kind);
    try std.testing.expectEqualStrings("A title", document.blocks[0].text.bytes());
    try std.testing.expectEqualStrings("cover.png", document.first_image().?);
    try std.testing.expectEqual(Kind.quote, document.blocks[3].kind);
}
