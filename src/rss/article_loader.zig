const std = @import("std");
const fetcher = @import("fetcher.zig");
const limits = @import("limits.zig");
const model = @import("model.zig");
const readable = @import("../parser/readable.zig");

pub const Outcome = union(enum) {
    content: model.Content,
    failure: anyerror,
};

pub const Completed = struct {
    url: model.ArticleUrl,
    outcome: Outcome,
};

const ResultQueue = std.Io.Queue(Completed);

pub const State = enum { idle, loading, ready, failed };

pub const Loader = struct {
    io: std.Io,
    client: std.http.Client,
    task: std.Io.Group = .init,
    result_buffer: [1]Completed = undefined,
    results: ResultQueue = undefined,
    state: State = .idle,
    requested_url: model.ArticleUrl = .{},
    response: [limits.article_page_response_bytes_max]u8 = undefined,
    redirect_buffer: [8 * 1_024]u8 = undefined,

    pub fn init_in_place(
        self: *Loader,
        allocator: std.mem.Allocator,
        io: std.Io,
    ) void {
        self.io = io;
        self.client = .{ .allocator = allocator, .io = io };
        self.task = .init;
        self.results = .init(&self.result_buffer);
        self.state = .idle;
        self.requested_url = .{};
    }

    pub fn deinit(self: *Loader) void {
        self.task.cancel(self.io);
        self.results.close(self.io);
        self.client.deinit();
    }

    pub fn request(self: *Loader, url: []const u8) !bool {
        if (url.len == 0) return false;
        if (std.mem.eql(u8, self.requested_url.bytes(), url)) return false;
        if (self.state == .loading) return false;
        model.set_truncated(&self.requested_url, url);
        try fetcher.prepare_tls(&self.client);
        self.task.concurrent(
            self.io,
            article_task,
            .{ self, self.requested_url },
        ) catch |err| {
            self.state = .failed;
            return err;
        };
        self.state = .loading;
        return true;
    }

    pub fn poll(self: *Loader) !?Completed {
        if (self.state != .loading) return null;
        var completed: [1]Completed = undefined;
        const count = self.results.get(self.io, &completed, 0) catch |err| {
            return switch (err) {
                error.Closed => null,
                error.Canceled => err,
            };
        };
        if (count == 0) return null;
        try self.task.await(self.io);
        self.state = switch (completed[0].outcome) {
            .content => .ready,
            .failure => .failed,
        };
        return completed[0];
    }
};

fn article_task(
    loader: *Loader,
    url: model.ArticleUrl,
) std.Io.Cancelable!void {
    const outcome: Outcome = if (fetch_article(loader, url.bytes())) |content|
        .{ .content = content }
    else |err|
        .{ .failure = err };
    loader.results.putOne(loader.io, .{
        .url = url,
        .outcome = outcome,
    }) catch |err| switch (err) {
        error.Closed => return,
        error.Canceled => return error.Canceled,
    };
}

fn fetch_article(loader: *Loader, url: []const u8) !model.Content {
    var writer = std.Io.Writer.fixed(&loader.response);
    const result = try loader.client.fetch(.{
        .location = .{ .url = url },
        .redirect_buffer = &loader.redirect_buffer,
        .response_writer = &writer,
        .headers = .{ .user_agent = .{ .override = "markix-rss/0.1" } },
    });
    if (result.status.class() != .success) return error.ArticleRequestFailed;
    if (writer.buffered().len == loader.response.len) {
        return error.ArticleResponseTooLarge;
    }
    var content = model.Content{};
    if (!readable.extract(writer.buffered(), &content)) {
        return error.ReadableArticleNotFound;
    }
    return content;
}
