const std = @import("std");
const limits = @import("limits.zig");
const model = @import("model.zig");

pub const LoadResult = struct {
    count: u16,
    path: model.FeedUrl,
};

pub fn load(
    io: std.Io,
    home: []const u8,
    feeds: *[limits.feed_count_max]model.Feed,
    storage: *[limits.feed_response_bytes_max]u8,
) !LoadResult {
    var path_buffer: [limits.path_bytes_max]u8 = undefined;
    const candidates = [_][]const u8{
        try std.fmt.bufPrint(
            &path_buffer,
            "{s}/Developer/ads-zaneyos/config/newsboat/urls",
            .{home},
        ),
        "",
        "",
    };
    var newsboat_path: [limits.path_bytes_max]u8 = undefined;
    var config_path: [limits.path_bytes_max]u8 = undefined;
    const paths = [_][]const u8{
        candidates[0],
        try std.fmt.bufPrint(&newsboat_path, "{s}/.newsboat/urls", .{home}),
        try std.fmt.bufPrint(&config_path, "{s}/.config/newsboat/urls", .{home}),
    };
    for (paths) |path| {
        const bytes = std.Io.Dir.cwd().readFile(io, path, storage) catch |err| {
            if (err == error.FileNotFound) continue;
            return err;
        };
        if (bytes.len == storage.len) return error.SubscriptionFileTooLarge;
        return .{
            .count = try parse(bytes, feeds),
            .path = model.FeedUrl.init(path) catch return error.SubscriptionPathTooLong,
        };
    }
    return error.SubscriptionFileNotFound;
}

pub fn parse(
    source: []const u8,
    feeds: *[limits.feed_count_max]model.Feed,
) !u16 {
    var count: u16 = 0;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (line[0] == '#') continue;
        if (count == limits.feed_count_max) return error.TooManyFeeds;
        feeds[count] = try parse_line(line);
        count += 1;
    }
    if (count == 0) return error.NoFeeds;
    return count;
}

pub fn make_feed(url: []const u8, category_value: []const u8) !model.Feed {
    if (!valid_feed_url(url)) return error.InvalidFeedUrl;
    const category = if (category_value.len == 0) "Unsorted" else category_value;
    if (std.mem.indexOfAny(u8, category, "\"\r\n") != null) {
        return error.InvalidFeedCategory;
    }
    return .{
        .title = try model.FeedTitle.init(feed_host(url)),
        .url = try model.FeedUrl.init(url),
        .category = try model.CategoryName.init(category),
    };
}

pub fn save(
    io: std.Io,
    path: []const u8,
    feeds: *const [limits.feed_count_max]model.Feed,
    feed_count: u16,
    keep: *const [limits.feed_count_max]bool,
    storage: *[limits.feed_response_bytes_max]u8,
) !void {
    const bytes = try encode(feeds, feed_count, keep, storage);
    const directory_path = std.fs.path.dirname(path) orelse return error.InvalidPath;
    const file_name = std.fs.path.basename(path);
    var directory = try std.Io.Dir.openDirAbsolute(io, directory_path, .{});
    defer directory.close(io);
    var atomic_file = try directory.createFileAtomic(
        io,
        file_name,
        .{ .replace = true },
    );
    defer atomic_file.deinit(io);
    try atomic_file.file.writeStreamingAll(io, bytes);
    try atomic_file.replace(io);
}

fn encode(
    feeds: *const [limits.feed_count_max]model.Feed,
    feed_count: u16,
    keep: *const [limits.feed_count_max]bool,
    storage: *[limits.feed_response_bytes_max]u8,
) ![]const u8 {
    if (feed_count > limits.feed_count_max) return error.TooManyFeeds;
    var writer = std.Io.Writer.fixed(storage);
    var index: u16 = 0;
    while (index < feed_count) : (index += 1) {
        if (!keep[index]) continue;
        const feed = &feeds[index];
        if (std.mem.indexOfAny(u8, feed.category.bytes(), "\"\r\n") != null) {
            return error.InvalidFeedCategory;
        }
        try writer.print(
            "{s} \"{s}\"\n",
            .{ feed.url.bytes(), feed.category.bytes() },
        );
    }
    return writer.buffered();
}

fn parse_line(line: []const u8) !model.Feed {
    const url_end = std.mem.indexOfAny(u8, line, " \t") orelse line.len;
    const url = line[0..url_end];
    if (!valid_feed_url(url)) return error.InvalidFeedUrl;
    const tags = std.mem.trim(u8, line[url_end..], " \t");
    const category = first_tag(tags);
    return make_feed(url, category);
}

fn first_tag(tags: []const u8) []const u8 {
    if (tags.len == 0) return "";
    if (tags[0] == '"') {
        const end = std.mem.indexOfScalarPos(u8, tags, 1, '"') orelse tags.len;
        return tags[1..end];
    }
    const end = std.mem.indexOfAny(u8, tags, " \t") orelse tags.len;
    return tags[0..end];
}

fn valid_feed_url(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "https://") or
        std.mem.startsWith(u8, url, "http://") or
        std.mem.startsWith(u8, url, "file://");
}

fn feed_host(url: []const u8) []const u8 {
    const scheme = std.mem.indexOf(u8, url, "://") orelse return url;
    const start = scheme + 3;
    const end = std.mem.indexOfScalarPos(u8, url, start, '/') orelse url.len;
    return url[start..end];
}

test "Newsboat subscriptions preserve quoted and bare categories" {
    const source =
        \\# A group.
        \\https://example.com/feed.xml "Technology"
        \\http://math.test/rss Maths extra
        \\
    ;
    var feeds: [limits.feed_count_max]model.Feed = undefined;
    const count = try parse(source, &feeds);
    try std.testing.expectEqual(@as(u16, 2), count);
    try std.testing.expectEqualStrings("Technology", feeds[0].category.bytes());
    try std.testing.expectEqualStrings("Maths", feeds[1].category.bytes());
    try std.testing.expectEqualStrings("example.com", feeds[0].title.bytes());
}

test "subscription encoding applies a bounded keep set" {
    var feeds: [limits.feed_count_max]model.Feed = undefined;
    feeds[0] = try make_feed("https://one.test/rss", "Tech");
    feeds[1] = try make_feed("https://two.test/rss", "News");
    var keep: [limits.feed_count_max]bool = @splat(false);
    keep[1] = true;
    var storage: [limits.feed_response_bytes_max]u8 = undefined;
    const bytes = try encode(&feeds, 2, &keep, &storage);
    try std.testing.expectEqualStrings(
        "https://two.test/rss \"News\"\n",
        bytes,
    );
}
