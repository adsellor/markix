const std = @import("std");
const limits = @import("limits.zig");
const FixedText = @import("../app/bookmarks/fixed_text.zig").FixedText;

pub const ArticleTitle = FixedText(limits.article_title_bytes_max);
pub const ArticleUrl = FixedText(limits.article_url_bytes_max);
pub const Content = FixedText(limits.article_content_bytes_max);
pub const CategoryName = FixedText(limits.category_name_bytes_max);
pub const FeedTitle = FixedText(limits.feed_title_bytes_max);
pub const FeedUrl = FixedText(limits.article_url_bytes_max);
pub const Published = FixedText(limits.published_bytes_max);
pub const ImageUrl = FixedText(limits.article_image_url_bytes_max);
pub const Summary = FixedText(limits.article_summary_bytes_max);

pub const Feed = struct {
    title: FeedTitle,
    url: FeedUrl,
    category: CategoryName,
    fetched: bool = false,
    failed: bool = false,
    article_count: u16 = 0,
};

pub const Article = struct {
    title: ArticleTitle,
    url: ArticleUrl,
    content: Content = .{},
    image_url: ImageUrl = .{},
    summary: Summary = .{},
    published: Published = .{},
    published_timestamp: i64 = 0,
    content_complete: bool = false,
    feed_index: u16,
    read: bool = false,

    pub fn matches(self: *const Article, feed: *const Feed, query: []const u8) bool {
        if (query.len == 0) return true;
        return contains_ignore_case(self.title.bytes(), query) or
            contains_ignore_case(self.url.bytes(), query) or
            contains_ignore_case(self.content.bytes(), query) or
            contains_ignore_case(self.summary.bytes(), query) or
            contains_ignore_case(feed.title.bytes(), query);
    }
};

pub fn set_truncated(target: anytype, value: []const u8) void {
    const capacity = target.buffer.len;
    target.set(value[0..@min(value.len, capacity)]) catch unreachable;
}

fn contains_ignore_case(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var start: usize = 0;
    while (start + needle.len <= haystack.len) : (start += 1) {
        var matches = true;
        for (needle, 0..) |byte, index| {
            if (std.ascii.toLower(haystack[start + index]) !=
                std.ascii.toLower(byte))
            {
                matches = false;
                break;
            }
        }
        if (matches) return true;
    }
    return false;
}

test "article search includes feed and summary metadata" {
    const feed = Feed{
        .title = try FeedTitle.init("Example Engineering"),
        .url = try FeedUrl.init("https://example.com/feed.xml"),
        .category = try CategoryName.init("Technology"),
    };
    var article = Article{
        .title = try ArticleTitle.init("A bounded system"),
        .url = try ArticleUrl.init("https://example.com/article"),
        .feed_index = 0,
    };
    try article.summary.set("Designed for predictable operation.");
    try std.testing.expect(article.matches(&feed, "ENGINEERING"));
    try std.testing.expect(article.matches(&feed, "predictable"));
    try std.testing.expect(!article.matches(&feed, "cooking"));
}
