const std = @import("std");
const framework = @import("../framework.zig");
const document = @import("../parser/document.zig");
const bookmarks = @import("../app/bookmarks.zig");
const bookmark_limits = @import("../app/limits.zig");
const FixedText = @import("../app/bookmarks/fixed_text.zig").FixedText;
const cache_module = @import("cache.zig");
const article_loader_module = @import("article_loader.zig");
const fetcher_module = @import("fetcher.zig");
const image_loader_module = @import("image_loader.zig");
const limits = @import("limits.zig");
const model = @import("model.zig");
const parser = @import("parser.zig");
const state_module = @import("state.zig");
const subscriptions = @import("subscriptions.zig");

const Message = FixedText(192);
const SearchInput = framework.widgets.TextInput(limits.search_bytes_max);
const FeedUrlInput = framework.widgets.TextInput(limits.article_url_bytes_max);
const FeedCategoryInput = framework.widgets.TextInput(limits.category_name_bytes_max);

pub const Focus = enum { categories, feeds, articles, reader };
pub const Scope = enum { all, unread, category };
pub const FeedMode = enum { browse, add_url, add_category, remove_confirm, prune_confirm };

const FetchOutcome = union(enum) {
    update: parser.Update,
    failure: anyerror,
};

const FetchResult = struct {
    worker_index: u16,
    feed_index: u16,
    outcome: FetchOutcome,
};

const FetchResultQueue = std.Io.Queue(FetchResult);

pub const Application = struct {
    io: std.Io,
    http_client: std.http.Client,
    fetchers: [limits.feed_fetch_concurrency]fetcher_module.Fetcher,
    fetch_tasks: [limits.feed_fetch_concurrency]std.Io.Group =
        @splat(.init),
    fetch_workers_busy: [limits.feed_fetch_concurrency]bool = @splat(false),
    fetch_result_buffer: [limits.feed_fetch_concurrency]FetchResult = undefined,
    fetch_results: FetchResultQueue = undefined,
    fetch_in_progress: bool = false,
    fetch_busy_count: u16 = 0,
    fetch_next: u16 = 0,
    fetch_stop: u16 = 0,
    fetch_success_count: u16 = 0,
    fetch_failure_count: u16 = 0,
    full_refresh_completed: bool = false,
    refresh_all_active: bool = false,

    feeds: [limits.feed_count_max]model.Feed = undefined,
    feed_count: u16 = 0,
    categories: [limits.category_count_max]model.CategoryName = undefined,
    category_count: u16 = 0,
    articles: [limits.article_count_max]model.Article = undefined,
    article_count: u16 = 0,
    unread_article_count: u16 = 0,
    feed_unread_counts: [limits.feed_count_max]u16 = @splat(0),
    read_state: state_module.State = .{},
    state_persistence: state_module.Persistence,
    cache_persistence: cache_module.Persistence,
    image_loader: image_loader_module.Loader,
    article_loader: article_loader_module.Loader,

    bookmark_store: bookmarks.Store = .{},
    bookmark_persistence: bookmarks.Persistence,
    subscription_path: model.FeedUrl = .{},

    filtered_feeds: [limits.feed_count_max]u16 = undefined,
    filtered_feed_count: u16 = 0,
    filtered_articles: [limits.article_count_max]u16 = undefined,
    filtered_article_count: u16 = 0,

    focus: Focus = .articles,
    scope: Scope = .all,
    active_category: model.CategoryName = .{},
    active_feed: ?u16 = null,
    category_cursor: u16 = 0,
    category_scroll: u16 = 0,
    category_viewport: u16 = 1,
    feed_cursor: u16 = 0,
    feed_scroll: u16 = 0,
    feed_viewport: u16 = 1,
    article_cursor: u16 = 0,
    article_scroll: u16 = 0,
    article_viewport: u16 = 1,
    reader_scroll: u16 = 0,
    reader_line_count: u16 = 0,
    reader_viewport: u16 = 1,
    reader_document: document.Document = .{},
    reader_document_article: ?u16 = null,
    reader_document_length: u16 = 0,
    reader_layout_valid: bool = false,
    reader_layout_width: u16 = 0,
    reader_layout_image: bool = false,
    reader_block_lines: [document.block_count_max]u16 = @splat(0),
    reader_only: bool = false,
    collapsed: [4]bool = @splat(false),
    search_open: bool = false,
    search: SearchInput = .{},
    applied_search: SearchInput = .{},
    feed_mode: FeedMode = .browse,
    feed_url_input: FeedUrlInput = .{},
    feed_category_input: FeedCategoryInput = .{},
    help_open: bool = false,
    message: Message = .{},

    pub fn create(
        allocator: std.mem.Allocator,
        io: std.Io,
        home: []const u8,
    ) !*Application {
        const application = try allocator.create(Application);
        errdefer allocator.destroy(application);
        application.initialize(io);
        application.http_client = .{ .allocator = allocator, .io = io };
        try application.image_loader.init_in_place(allocator, io, home);
        errdefer application.image_loader.deinit();
        application.article_loader.init_in_place(allocator, io);
        errdefer application.article_loader.deinit();
        try application.state_persistence.init_in_place(home);
        try application.cache_persistence.init_in_place(home);
        try application.bookmark_persistence.init_in_place(home);
        application.fetch_results = .init(&application.fetch_result_buffer);
        try application.set_message("Loading subscriptions");
        return application;
    }

    fn initialize(self: *Application, io: std.Io) void {
        self.io = io;
        self.fetch_tasks = @splat(.init);
        self.fetch_workers_busy = @splat(false);
        self.fetch_in_progress = false;
        self.fetch_busy_count = 0;
        self.fetch_next = 0;
        self.fetch_stop = 0;
        self.fetch_success_count = 0;
        self.fetch_failure_count = 0;
        self.full_refresh_completed = false;
        self.refresh_all_active = false;
        self.feed_count = 0;
        self.category_count = 0;
        self.article_count = 0;
        self.unread_article_count = 0;
        self.feed_unread_counts = @splat(0);
        self.read_state = .{};
        self.bookmark_store = .{};
        self.subscription_path = .{};
        self.filtered_feed_count = 0;
        self.filtered_article_count = 0;
        self.focus = .articles;
        self.scope = .all;
        self.active_category = .{};
        self.active_feed = null;
        self.category_cursor = 0;
        self.category_scroll = 0;
        self.category_viewport = 1;
        self.feed_cursor = 0;
        self.feed_scroll = 0;
        self.feed_viewport = 1;
        self.article_cursor = 0;
        self.article_scroll = 0;
        self.article_viewport = 1;
        self.reader_scroll = 0;
        self.reader_line_count = 0;
        self.reader_viewport = 1;
        self.reader_document = .{};
        self.reader_document_article = null;
        self.reader_document_length = 0;
        self.reader_layout_valid = false;
        self.reader_layout_width = 0;
        self.reader_layout_image = false;
        self.reader_block_lines = @splat(0);
        self.reader_only = false;
        self.collapsed = @splat(false);
        self.search_open = false;
        self.search = .{};
        self.applied_search = .{};
        self.feed_mode = .browse;
        self.feed_url_input = .{};
        self.feed_category_input = .{};
        self.help_open = false;
        self.message = .{};
    }

    pub fn destroy(self: *Application, allocator: std.mem.Allocator) void {
        var worker_index: u16 = 0;
        while (worker_index < limits.feed_fetch_concurrency) : (worker_index += 1) {
            self.fetch_tasks[worker_index].cancel(self.io);
        }
        self.fetch_results.close(self.io);
        const cache_failure = self.cache_persistence.finish(
            self.io,
            &self.feeds,
            self.feed_count,
            &self.articles,
            self.article_count,
        ) catch |err| failure: {
            std.log.err("failed to finish RSS cache task: {s}", .{@errorName(err)});
            break :failure null;
        };
        if (cache_failure) |err| {
            std.log.err("failed to finish RSS cache save: {s}", .{@errorName(err)});
        }
        self.image_loader.deinit();
        self.article_loader.deinit();
        self.cache_persistence.deinit(self.io);
        self.http_client.deinit();
        allocator.destroy(self);
    }

    pub fn load(self: *Application, home: []const u8) !void {
        try self.state_persistence.load(self.io, &self.read_state);
        const result = try subscriptions.load(
            self.io,
            home,
            &self.feeds,
            &self.fetchers[0].response,
        );
        self.feed_count = result.count;
        self.subscription_path = result.path;
        const cache_fresh = try self.load_cache();
        self.rebuild_categories();
        self.refresh_feeds();
        self.refresh_articles();
        if (cache_fresh) {
            try self.set_message("Cached articles loaded; press R to refresh");
        } else {
            try self.set_message("Cache stale or empty; refreshing feeds");
            try self.start_refresh_all();
        }
    }

    fn load_cache(self: *Application) !bool {
        self.article_count = 0;
        const cached_at = self.cache_persistence.load(
            self.io,
            &self.feeds,
            self.feed_count,
            &self.articles,
            &self.article_count,
        ) catch |err| {
            self.article_count = 0;
            if (err == error.InvalidCache) return false;
            return err;
        } orelse return false;
        self.hydrate_cached_articles();
        return cache_module.is_fresh(cached_at, self.io);
    }

    fn hydrate_cached_articles(self: *Application) void {
        var feed_index: u16 = 0;
        while (feed_index < self.feed_count) : (feed_index += 1) {
            self.feeds[feed_index].article_count = 0;
        }
        var article_index: u16 = 0;
        while (article_index < self.article_count) : (article_index += 1) {
            const article = &self.articles[article_index];
            article.read = self.read_state.contains(article.url.bytes());
            self.feeds[article.feed_index].article_count += 1;
        }
    }

    pub fn handle_key(self: *Application, key: framework.input.Key) !bool {
        if (self.help_open) return self.handle_help(key);
        switch (key) {
            .character => |byte| if (byte == '?') {
                self.help_open = true;
                self.reader_only = false;
                return true;
            },
            else => {},
        }
        if (self.feed_mode != .browse) return self.handle_feed_mode(key);
        if (self.search_open) return self.handle_search(key);
        return switch (key) {
            .character => |byte| self.handle_character(byte),
            .enter => self.activate(),
            .escape => self.handle_escape(),
            .tab => self.cycle_focus(1),
            .shift_tab => self.cycle_focus(-1),
            .left => self.cycle_focus(-1),
            .right => self.cycle_focus(1),
            .up => self.move_focused(-1),
            .down => self.move_focused(1),
            .home => self.move_to_edge(false),
            .end => self.move_to_edge(true),
            .control => |byte| self.handle_control(byte),
            else => true,
        };
    }

    fn handle_help(self: *Application, key: framework.input.Key) bool {
        switch (key) {
            .escape => self.help_open = false,
            .character => |byte| if (byte == '?' or byte == 'q') {
                self.help_open = false;
            },
            else => {},
        }
        return true;
    }

    fn handle_character(self: *Application, byte: u8) !bool {
        switch (byte) {
            'q' => return false,
            'j' => _ = self.move_focused(1),
            'k' => _ = self.move_focused(-1),
            'h' => _ = self.cycle_focus(-1),
            'l' => _ = self.cycle_focus(1),
            'g' => _ = self.move_to_edge(false),
            'G' => _ = self.move_to_edge(true),
            '/' => self.search_open = true,
            'o' => try self.open_selected(),
            'i' => try self.open_selected_image(),
            'b' => try self.bookmark_selected(),
            'm' => try self.toggle_read(),
            'u' => self.select_scope(.unread, ""),
            'a' => self.select_scope(.all, ""),
            'r' => try self.start_refresh_selected(),
            'R' => try self.start_refresh_all(),
            'A' => try self.begin_add_feed(),
            'd' => try self.begin_remove_feed(),
            'P' => try self.begin_prune_feeds(),
            'c' => self.toggle_focused_section(),
            'v' => {
                self.reader_only = !self.reader_only;
                if (self.reader_only) {
                    self.focus = .reader;
                    self.collapsed[focus_index(.reader)] = false;
                } else {
                    self.focus = .articles;
                }
            },
            else => {},
        }
        return true;
    }

    fn handle_control(self: *Application, byte: u8) !bool {
        switch (byte) {
            'c' => return false,
            'd' => self.move_page(1),
            'u' => self.move_page(-1),
            else => {},
        }
        return true;
    }

    fn handle_feed_mode(self: *Application, key: framework.input.Key) !bool {
        return switch (self.feed_mode) {
            .browse => true,
            .add_url, .add_category => self.handle_add_feed(key),
            .remove_confirm => self.handle_remove_confirm(key),
            .prune_confirm => self.handle_prune_confirm(key),
        };
    }

    fn handle_add_feed(self: *Application, key: framework.input.Key) !bool {
        if (key == .escape) {
            self.feed_mode = .browse;
            try self.set_message("Feed add cancelled");
            return true;
        }
        if (key == .tab or key == .shift_tab) {
            self.feed_mode = if (self.feed_mode == .add_url) .add_category else .add_url;
            return true;
        }
        const action = if (self.feed_mode == .add_url)
            try self.feed_url_input.handle(key)
        else
            try self.feed_category_input.handle(key);
        if (action != .submitted) return true;
        if (self.feed_mode == .add_url) {
            self.feed_mode = .add_category;
            try self.set_message("Enter a category, then press Enter");
        } else {
            try self.commit_add_feed();
        }
        return true;
    }

    fn handle_remove_confirm(self: *Application, key: framework.input.Key) !bool {
        switch (key) {
            .character => |byte| if (byte == 'd') {
                try self.remove_selected_feed();
                return true;
            },
            else => {},
        }
        self.feed_mode = .browse;
        try self.set_message("Feed removal cancelled");
        return true;
    }

    fn handle_prune_confirm(self: *Application, key: framework.input.Key) !bool {
        switch (key) {
            .character => |byte| if (byte == 'P') {
                try self.prune_failed_feeds();
                return true;
            },
            else => {},
        }
        self.feed_mode = .browse;
        try self.set_message("Feed pruning cancelled");
        return true;
    }

    fn handle_search(self: *Application, key: framework.input.Key) !bool {
        switch (key) {
            .escape => {
                self.search.clear();
                self.applied_search.clear();
                self.search_open = false;
                self.refresh_articles();
                try self.set_message("Search cleared");
                return true;
            },
            .enter => {
                try self.applied_search.set(self.search.value());
                self.search_open = false;
                self.refresh_articles();
                try self.set_message("Search applied");
                return true;
            },
            .up => {
                self.move_articles(-1);
                return true;
            },
            .down => {
                self.move_articles(1);
                return true;
            },
            .control => |byte| {
                if (byte == 'c') return false;
                if (byte == 'p') self.move_articles(-1);
                if (byte == 'n') self.move_articles(1);
                return true;
            },
            else => {},
        }
        _ = try self.search.handle(key);
        return true;
    }

    fn handle_escape(self: *Application) bool {
        if (self.reader_only) {
            self.reader_only = false;
            self.focus = .articles;
        }
        return true;
    }

    fn activate(self: *Application) !bool {
        switch (self.focus) {
            .categories => self.apply_category_cursor(),
            .feeds => self.apply_feed_cursor(),
            .articles => try self.open_selected(),
            .reader => {
                self.reader_only = !self.reader_only;
                self.collapsed[focus_index(.reader)] = false;
                if (!self.reader_only) self.focus = .articles;
            },
        }
        return true;
    }

    pub fn poll_background(self: *Application) !bool {
        const article_changed = try self.poll_article_loader();
        const image_changed = try self.image_loader.poll();
        const cache_changed = try self.poll_cache();
        if (!self.fetch_in_progress) {
            return article_changed or image_changed or cache_changed;
        }
        var completed: [limits.feed_fetch_concurrency]FetchResult = undefined;
        const count = self.fetch_results.get(self.io, &completed, 0) catch |err| {
            return switch (err) {
                error.Closed => article_changed or image_changed or cache_changed,
                error.Canceled => err,
            };
        };
        if (count == 0) return article_changed or image_changed or cache_changed;
        std.debug.assert(count <= limits.feed_fetch_concurrency);
        for (completed[0..count]) |*result| {
            const worker_index = result.worker_index;
            try self.fetch_tasks[worker_index].await(self.io);
            std.debug.assert(self.fetch_workers_busy[worker_index]);
            std.debug.assert(self.fetch_busy_count > 0);
            self.fetch_workers_busy[worker_index] = false;
            self.fetch_busy_count -= 1;
            self.apply_fetch_result(result);
        }
        try self.schedule_available_feeds();
        self.fetch_in_progress = self.fetch_busy_count > 0;
        self.refresh_feeds();
        self.refresh_articles();
        try self.set_refresh_message();
        if (!self.fetch_in_progress) {
            if (self.refresh_all_active) self.full_refresh_completed = true;
            self.refresh_all_active = false;
            try self.save_cache();
        }
        return true;
    }

    fn poll_cache(self: *Application) !bool {
        const failure = try self.cache_persistence.poll(
            self.io,
            &self.feeds,
            self.feed_count,
            &self.articles,
            self.article_count,
        );
        if (failure) |err| {
            try self.set_message(@errorName(err));
            return true;
        }
        return false;
    }

    pub fn request_selected_image(self: *Application) !bool {
        const article = self.selected_article() orelse return false;
        return self.image_loader.request(article.image_url.bytes()) catch |err| {
            try self.set_message(@errorName(err));
            return false;
        };
    }

    pub fn request_selected_content(self: *Application) !bool {
        const article = self.selected_article() orelse return false;
        if (article.content_complete) return false;
        const started = self.article_loader.request(article.url.bytes()) catch |err| {
            try self.set_message(@errorName(err));
            return false;
        };
        if (started) try self.set_message("Fetching the full article...");
        return started;
    }

    pub fn selected_image_path(self: *const Application) ?[]const u8 {
        if (self.article_cursor >= self.filtered_article_count) return null;
        const article = &self.articles[self.filtered_articles[self.article_cursor]];
        return self.image_loader.ready_path(article.image_url.bytes());
    }

    fn poll_article_loader(self: *Application) !bool {
        const completed = try self.article_loader.poll() orelse return false;
        switch (completed.outcome) {
            .failure => |err| try self.set_message(@errorName(err)),
            .content => |content| try self.apply_full_content(
                completed.url.bytes(),
                content,
            ),
        }
        return true;
    }

    fn apply_full_content(
        self: *Application,
        url: []const u8,
        content: model.Content,
    ) !void {
        const index = self.find_article(url) orelse {
            try self.set_message("Fetched article is no longer loaded");
            return;
        };
        const article = &self.articles[index];
        article.content = content;
        article.content_complete = true;
        self.reader_document_article = null;
        self.reader_layout_valid = false;
        const parsed = document.parse(article.content.bytes());
        document.write_plain(&parsed, &article.summary);
        if (parsed.first_image()) |image| {
            if (valid_http_url(image)) model.set_truncated(&article.image_url, image);
        }
        try self.save_cache();
        try self.set_message("Full article loaded and cached");
    }

    fn save_cache(self: *Application) !void {
        self.cache_persistence.request_save(
            self.io,
            &self.feeds,
            self.feed_count,
            &self.articles,
            self.article_count,
        ) catch |err| {
            try self.set_message(@errorName(err));
        };
    }

    fn apply_fetch_result(self: *Application, result: *const FetchResult) void {
        const feed = &self.feeds[result.feed_index];
        feed.fetched = true;
        switch (result.outcome) {
            .failure => {
                feed.failed = true;
                self.fetch_failure_count += 1;
            },
            .update => |*update| {
                feed.failed = false;
                self.fetch_success_count += 1;
                if (!update.title.is_empty()) feed.title = update.title;
                self.merge_articles(update);
            },
        }
    }

    fn set_refresh_message(self: *Application) !void {
        if (self.fetch_next < self.fetch_stop or self.fetch_busy_count > 0) {
            var buffer: [96]u8 = undefined;
            const value = try std.fmt.bufPrint(
                &buffer,
                "Refreshing {d}/{d} | {d} articles",
                .{ self.fetch_next, self.fetch_stop, self.article_count },
            );
            try self.set_message(value);
        } else {
            var buffer: [128]u8 = undefined;
            const value = try std.fmt.bufPrint(
                &buffer,
                "Refresh complete | {d} feeds | {d} failed | {d} articles",
                .{ self.fetch_success_count, self.fetch_failure_count, self.article_count },
            );
            try self.set_message(value);
        }
    }

    fn merge_articles(self: *Application, update: *const parser.Update) void {
        var index: u16 = 0;
        while (index < update.article_count) : (index += 1) {
            const source = update.articles[index];
            if (self.find_article(source.url.bytes()) != null) continue;
            self.insert_article(source);
        }
    }

    fn insert_article(self: *Application, source: model.Article) void {
        const destination = if (self.article_count < limits.article_count_max) block: {
            const index = self.article_count;
            self.article_count += 1;
            break :block index;
        } else block: {
            const index = self.oldest_article_index();
            if (source.published_timestamp <=
                self.articles[index].published_timestamp) return;
            const old_feed = self.articles[index].feed_index;
            self.feeds[old_feed].article_count -|= 1;
            break :block index;
        };
        self.articles[destination] = source;
        self.articles[destination].read = self.read_state.contains(source.url.bytes());
        self.feeds[source.feed_index].article_count += 1;
    }

    fn oldest_article_index(self: *const Application) u16 {
        std.debug.assert(self.article_count == limits.article_count_max);
        var oldest: u16 = 0;
        var index: u16 = 1;
        while (index < self.article_count) : (index += 1) {
            if (self.articles[index].published_timestamp <
                self.articles[oldest].published_timestamp) oldest = index;
        }
        return oldest;
    }

    fn find_article(self: *const Application, url: []const u8) ?u16 {
        var index: u16 = 0;
        while (index < self.article_count) : (index += 1) {
            if (std.mem.eql(u8, self.articles[index].url.bytes(), url)) return index;
        }
        return null;
    }

    fn begin_add_feed(self: *Application) !void {
        if (self.fetch_in_progress) {
            try self.set_message("Wait for the current refresh before adding a feed");
            return;
        }
        if (self.feed_count == limits.feed_count_max) {
            try self.set_message("Feed limit reached");
            return;
        }
        self.feed_url_input.clear();
        self.feed_category_input.clear();
        self.feed_mode = .add_url;
        self.reader_only = false;
        try self.set_message("Enter a feed URL, then press Enter");
    }

    fn commit_add_feed(self: *Application) !void {
        const feed = subscriptions.make_feed(
            self.feed_url_input.value(),
            self.feed_category_input.value(),
        ) catch |err| {
            try self.set_message(@errorName(err));
            return;
        };
        if (self.find_feed_url(feed.url.bytes()) != null) {
            try self.set_message("Feed is already subscribed");
            return;
        }
        const new_index = self.feed_count;
        self.feeds[new_index] = feed;
        var keep: [limits.feed_count_max]bool = @splat(false);
        @memset(keep[0 .. self.feed_count + 1], true);
        try self.persist_subscriptions(&keep, self.feed_count + 1);
        self.feed_count += 1;
        self.feed_mode = .browse;
        self.full_refresh_completed = false;
        self.rebuild_after_feed_change();
        self.active_feed = new_index;
        self.feed_cursor = new_index + 1;
        self.refresh_articles();
        try self.set_message("Feed added; refreshing it now");
        try self.start_refresh_selected();
    }

    fn begin_remove_feed(self: *Application) !void {
        if (self.focus != .feeds or self.active_feed == null) {
            try self.set_message("Focus a specific feed before removing it");
            return;
        }
        if (self.fetch_in_progress) {
            try self.set_message("Wait for the current refresh before removing a feed");
            return;
        }
        if (self.feed_count <= 1) {
            try self.set_message("The final feed cannot be removed");
            return;
        }
        self.feed_mode = .remove_confirm;
        try self.set_message("Press d again to remove this feed; any other key cancels");
    }

    fn remove_selected_feed(self: *Application) !void {
        const remove_index = self.active_feed orelse return;
        var keep: [limits.feed_count_max]bool = @splat(false);
        @memset(keep[0..self.feed_count], true);
        keep[remove_index] = false;
        try self.persist_subscriptions(&keep, self.feed_count);
        self.apply_feed_keep(&keep);
        self.feed_mode = .browse;
        try self.save_cache();
        try self.set_message("Feed removed");
    }

    fn begin_prune_feeds(self: *Application) !void {
        if (self.fetch_in_progress) {
            try self.set_message("Wait for the current refresh before pruning feeds");
            return;
        }
        if (!self.full_refresh_completed) {
            try self.set_message("Run R and finish a full refresh before pruning");
            return;
        }
        const failed = self.failed_feed_count();
        if (failed == 0) {
            try self.set_message("No unreachable feeds found");
            return;
        }
        self.feed_mode = .prune_confirm;
        var buffer: [128]u8 = undefined;
        const value = try std.fmt.bufPrint(
            &buffer,
            "Press P again to prune {d} failed feeds; any other key cancels",
            .{failed},
        );
        try self.set_message(value);
    }

    fn prune_failed_feeds(self: *Application) !void {
        var keep: [limits.feed_count_max]bool = @splat(false);
        var kept: u16 = 0;
        var index: u16 = 0;
        while (index < self.feed_count) : (index += 1) {
            keep[index] = !self.feeds[index].failed;
            kept += @intFromBool(keep[index]);
        }
        if (kept == 0) {
            self.feed_mode = .browse;
            try self.set_message("Prune refused: every feed failed");
            return;
        }
        try self.persist_subscriptions(&keep, self.feed_count);
        const removed = self.feed_count - kept;
        self.apply_feed_keep(&keep);
        self.feed_mode = .browse;
        try self.save_cache();
        var buffer: [64]u8 = undefined;
        const value = try std.fmt.bufPrint(&buffer, "Pruned {d} failed feeds", .{removed});
        try self.set_message(value);
    }

    fn start_refresh_all(self: *Application) !void {
        if (self.fetch_in_progress) {
            try self.set_message("A feed refresh is already running");
            return;
        }
        try fetcher_module.prepare_tls(&self.http_client);
        self.refresh_all_active = true;
        self.full_refresh_completed = false;
        var index: u16 = 0;
        while (index < self.feed_count) : (index += 1) {
            self.feeds[index].fetched = false;
            self.feeds[index].failed = false;
        }
        self.fetch_next = 0;
        self.fetch_stop = self.feed_count;
        self.fetch_success_count = 0;
        self.fetch_failure_count = 0;
        try self.schedule_available_feeds();
    }

    fn start_refresh_selected(self: *Application) !void {
        if (self.fetch_in_progress) {
            try self.set_message("A feed refresh is already running");
            return;
        }
        try fetcher_module.prepare_tls(&self.http_client);
        const feed_index = self.active_feed orelse {
            try self.start_refresh_all();
            return;
        };
        self.refresh_all_active = false;
        self.feeds[feed_index].fetched = false;
        self.feeds[feed_index].failed = false;
        self.fetch_next = feed_index;
        self.fetch_stop = feed_index + 1;
        self.fetch_success_count = 0;
        self.fetch_failure_count = 0;
        try self.schedule_available_feeds();
    }

    fn schedule_available_feeds(self: *Application) !void {
        std.debug.assert(self.http_client.now != null or std.http.Client.disable_tls);
        var worker_index: u16 = 0;
        while (worker_index < limits.feed_fetch_concurrency) : (worker_index += 1) {
            if (self.fetch_next >= self.fetch_stop) break;
            if (self.fetch_workers_busy[worker_index]) continue;
            try self.schedule_feed(worker_index);
        }
        self.fetch_in_progress = self.fetch_busy_count > 0;
    }

    fn schedule_feed(self: *Application, worker_index: u16) !void {
        std.debug.assert(worker_index < limits.feed_fetch_concurrency);
        std.debug.assert(!self.fetch_workers_busy[worker_index]);
        const feed_index = self.fetch_next;
        self.fetch_next += 1;
        self.fetch_tasks[worker_index].concurrent(
            self.io,
            fetch_task,
            .{
                self.io,
                &self.fetchers[worker_index],
                &self.http_client,
                &self.fetch_results,
                worker_index,
                feed_index,
                self.feeds[feed_index].url,
            },
        ) catch |err| {
            try self.set_message(@errorName(err));
            return;
        };
        self.fetch_workers_busy[worker_index] = true;
        self.fetch_busy_count += 1;
    }

    fn bookmark_selected(self: *Application) !void {
        const article = self.selected_article() orelse {
            try self.set_message("Nothing selected");
            return;
        };
        self.bookmark_store = .{};
        try self.bookmark_persistence.load(self.io, &self.bookmark_store);
        const feed = &self.feeds[article.feed_index];
        var tags_buffer: [96]u8 = undefined;
        const tags = std.fmt.bufPrint(
            &tags_buffer,
            "rss,{s}",
            .{feed.category.bytes()},
        ) catch "rss";
        var bookmark = bookmarks.Bookmark.init(
            article.title.bytes()[0..@min(
                article.title.bytes().len,
                bookmark_limits.bookmark_title_bytes_max,
            )],
            article.url.bytes(),
            tags,
            feed.title.bytes(),
        ) catch |err| {
            try self.set_message(@errorName(err));
            return;
        };
        model.set_truncated(&bookmark.description, article.summary.bytes());
        model.set_truncated(&bookmark.preview, article.summary.bytes());
        self.bookmark_store.add(bookmark) catch |err| {
            try self.set_message(if (err == error.DuplicateBookmark)
                "Already bookmarked in Markix"
            else
                @errorName(err));
            return;
        };
        try self.bookmark_persistence.save(self.io, &self.bookmark_store);
        try self.mark_selected_read();
        try self.set_message("Bookmarked in Markix");
    }

    fn open_selected(self: *Application) !void {
        const article = self.selected_article() orelse {
            try self.set_message("Nothing selected");
            return;
        };
        try bookmarks.browser.open(self.io, article.url.bytes());
        try self.mark_selected_read();
        try self.set_message("Opened in browser");
    }

    fn open_selected_image(self: *Application) !void {
        const article = self.selected_article() orelse {
            try self.set_message("Nothing selected");
            return;
        };
        const url = article.image_url.bytes();
        if (url.len == 0) {
            try self.set_message("This article has no image");
            return;
        }
        try bookmarks.browser.open(self.io, url);
        try self.set_message("Opened article image");
    }

    fn toggle_read(self: *Application) !void {
        const article = self.selected_article() orelse return;
        if (article.read) {
            article.read = false;
            self.read_state.mark_unread(article.url.bytes());
        } else {
            article.read = true;
            try self.read_state.mark_read(article.url.bytes());
        }
        try self.state_persistence.save(self.io, &self.read_state);
        self.refresh_feeds();
        self.refresh_articles();
        try self.set_message(if (article.read) "Marked read" else "Marked unread");
    }

    fn mark_selected_read(self: *Application) !void {
        const article = self.selected_article() orelse return;
        if (article.read) return;
        article.read = true;
        try self.read_state.mark_read(article.url.bytes());
        try self.state_persistence.save(self.io, &self.read_state);
        self.refresh_feeds();
        self.refresh_articles();
    }

    pub fn selected_article(self: *Application) ?*model.Article {
        if (self.article_cursor >= self.filtered_article_count) return null;
        return &self.articles[self.filtered_articles[self.article_cursor]];
    }

    pub fn selected_document(self: *Application) ?*const document.Document {
        if (self.article_cursor >= self.filtered_article_count) return null;
        const article_index = self.filtered_articles[self.article_cursor];
        const article = &self.articles[article_index];
        const source = if (article.content.is_empty())
            article.summary.bytes()
        else
            article.content.bytes();
        const source_length: u16 = @intCast(source.len);
        if (self.reader_document_article != article_index or
            self.reader_document_length != source_length)
        {
            self.reader_document = document.parse(source);
            self.reader_document_article = article_index;
            self.reader_document_length = source_length;
            self.reader_layout_valid = false;
        }
        return &self.reader_document;
    }

    pub fn unread_count(self: *const Application) u16 {
        return self.unread_article_count;
    }

    pub fn search_query(self: *const Application) []const u8 {
        return self.applied_search.value();
    }

    pub fn feed_unread_count(self: *const Application, feed_index: u16) u16 {
        if (feed_index >= self.feed_count) return 0;
        return self.feed_unread_counts[feed_index];
    }

    fn recount_unread(self: *Application) void {
        self.unread_article_count = 0;
        self.feed_unread_counts = @splat(0);
        var index: u16 = 0;
        while (index < self.article_count) : (index += 1) {
            const article = &self.articles[index];
            if (article.read) continue;
            self.unread_article_count += 1;
            self.feed_unread_counts[article.feed_index] += 1;
        }
    }

    fn find_feed_url(self: *const Application, url: []const u8) ?u16 {
        var index: u16 = 0;
        while (index < self.feed_count) : (index += 1) {
            if (std.mem.eql(u8, self.feeds[index].url.bytes(), url)) return index;
        }
        return null;
    }

    fn failed_feed_count(self: *const Application) u16 {
        var count: u16 = 0;
        var index: u16 = 0;
        while (index < self.feed_count) : (index += 1) {
            count += @intFromBool(self.feeds[index].failed);
        }
        return count;
    }

    fn persist_subscriptions(
        self: *Application,
        keep: *const [limits.feed_count_max]bool,
        count: u16,
    ) !void {
        try subscriptions.save(
            self.io,
            self.subscription_path.bytes(),
            &self.feeds,
            count,
            keep,
            &self.fetchers[0].response,
        );
    }

    fn apply_feed_keep(
        self: *Application,
        keep: *const [limits.feed_count_max]bool,
    ) void {
        var feed_map: [limits.feed_count_max]?u16 = @splat(null);
        var next_feed: u16 = 0;
        var feed_index: u16 = 0;
        while (feed_index < self.feed_count) : (feed_index += 1) {
            if (!keep[feed_index]) continue;
            feed_map[feed_index] = next_feed;
            self.feeds[next_feed] = self.feeds[feed_index];
            next_feed += 1;
        }
        self.feed_count = next_feed;
        self.compact_articles(&feed_map);
        self.full_refresh_completed = false;
        self.rebuild_after_feed_change();
    }

    fn compact_articles(
        self: *Application,
        feed_map: *const [limits.feed_count_max]?u16,
    ) void {
        var next_article: u16 = 0;
        var index: u16 = 0;
        while (index < self.article_count) : (index += 1) {
            const mapped = feed_map[self.articles[index].feed_index] orelse continue;
            self.articles[next_article] = self.articles[index];
            self.articles[next_article].feed_index = mapped;
            next_article += 1;
        }
        self.article_count = next_article;
        self.hydrate_cached_articles();
    }

    fn rebuild_after_feed_change(self: *Application) void {
        self.scope = .all;
        self.active_category.clear();
        self.active_feed = null;
        self.category_cursor = 0;
        self.feed_cursor = 0;
        self.article_cursor = 0;
        self.rebuild_categories();
        self.refresh_feeds();
        self.refresh_articles();
    }

    fn rebuild_categories(self: *Application) void {
        self.category_count = 0;
        var feed_index: u16 = 0;
        while (feed_index < self.feed_count) : (feed_index += 1) {
            const category = self.feeds[feed_index].category;
            if (self.find_category(category.bytes()) != null) continue;
            if (self.category_count == limits.category_count_max) break;
            self.categories[self.category_count] = category;
            self.category_count += 1;
        }
    }

    fn find_category(self: *const Application, name: []const u8) ?u16 {
        var index: u16 = 0;
        while (index < self.category_count) : (index += 1) {
            if (std.ascii.eqlIgnoreCase(self.categories[index].bytes(), name)) return index;
        }
        return null;
    }

    fn refresh_feeds(self: *Application) void {
        self.recount_unread();
        self.filtered_feed_count = 0;
        var index: u16 = 0;
        while (index < self.feed_count) : (index += 1) {
            const feed = &self.feeds[index];
            const visible = switch (self.scope) {
                .all => true,
                .unread => self.feed_unread_count(index) > 0,
                .category => std.ascii.eqlIgnoreCase(
                    feed.category.bytes(),
                    self.active_category.bytes(),
                ),
            };
            if (!visible) continue;
            self.filtered_feeds[self.filtered_feed_count] = index;
            self.filtered_feed_count += 1;
        }
        if (self.feed_cursor > self.filtered_feed_count) self.feed_cursor = 0;
        self.ensure_feed_visible();
    }

    fn refresh_articles(self: *Application) void {
        const selected_before = if (self.article_cursor < self.filtered_article_count)
            self.filtered_articles[self.article_cursor]
        else
            null;
        self.filtered_article_count = 0;
        var index: u16 = 0;
        while (index < self.article_count) : (index += 1) {
            const article = &self.articles[index];
            if (!self.article_visible(article)) continue;
            self.filtered_articles[self.filtered_article_count] = index;
            self.filtered_article_count += 1;
        }
        self.sort_filtered_articles();
        const selected_after = if (selected_before) |selected|
            self.find_filtered_article(selected)
        else
            null;
        if (selected_after) |cursor| {
            self.article_cursor = cursor;
        } else if (self.filtered_article_count == 0) {
            self.article_cursor = 0;
        } else if (self.article_cursor >= self.filtered_article_count) {
            self.article_cursor = self.filtered_article_count - 1;
        }
        const selected_now = if (self.article_cursor < self.filtered_article_count)
            self.filtered_articles[self.article_cursor]
        else
            null;
        if (selected_before != selected_now) self.reader_scroll = 0;
        self.ensure_article_visible();
    }

    fn find_filtered_article(self: *const Application, article_index: u16) ?u16 {
        var index: u16 = 0;
        while (index < self.filtered_article_count) : (index += 1) {
            if (self.filtered_articles[index] == article_index) return index;
        }
        return null;
    }

    fn sort_filtered_articles(self: *Application) void {
        std.mem.sortUnstable(
            u16,
            self.filtered_articles[0..self.filtered_article_count],
            self,
            article_index_is_newer,
        );
    }

    fn article_index_is_newer(self: *Application, lhs: u16, rhs: u16) bool {
        return self.article_is_newer(lhs, rhs);
    }

    fn article_is_newer(self: *const Application, lhs: u16, rhs: u16) bool {
        const lhs_time = self.articles[lhs].published_timestamp;
        const rhs_time = self.articles[rhs].published_timestamp;
        if (lhs_time != rhs_time) return lhs_time > rhs_time;
        return lhs > rhs;
    }

    fn article_visible(self: *const Application, article: *const model.Article) bool {
        if (self.scope == .unread and article.read) return false;
        if (self.scope == .category) {
            const category = self.feeds[article.feed_index].category.bytes();
            if (!std.ascii.eqlIgnoreCase(category, self.active_category.bytes())) return false;
        }
        if (self.active_feed) |feed_index| {
            if (article.feed_index != feed_index) return false;
        }
        return article.matches(
            &self.feeds[article.feed_index],
            self.applied_search.value(),
        );
    }

    fn select_scope(self: *Application, scope: Scope, category: []const u8) void {
        self.scope = scope;
        self.active_category.clear();
        if (scope == .category) {
            self.active_category.set(category) catch unreachable;
        }
        self.active_feed = null;
        self.feed_cursor = 0;
        self.article_cursor = 0;
        self.refresh_feeds();
        self.refresh_articles();
    }

    fn apply_category_cursor(self: *Application) void {
        if (self.category_cursor == 0) {
            self.select_scope(.all, "");
        } else if (self.category_cursor == 1) {
            self.select_scope(.unread, "");
        } else {
            const index = self.category_cursor - 2;
            if (index < self.category_count) {
                self.select_scope(.category, self.categories[index].bytes());
            }
        }
    }

    fn apply_feed_cursor(self: *Application) void {
        self.active_feed = if (self.feed_cursor == 0)
            null
        else if (self.feed_cursor - 1 < self.filtered_feed_count)
            self.filtered_feeds[self.feed_cursor - 1]
        else
            null;
        self.article_cursor = 0;
        self.refresh_articles();
    }

    fn cycle_focus(self: *Application, delta: i8) bool {
        const count: i8 = 4;
        const current: i8 = @intCast(@backingInt(self.focus));
        const next = @mod(current + delta, count);
        self.focus = @fromBackingInt(@intCast(next));
        self.reader_only = false;
        return true;
    }

    pub fn is_collapsed(self: *const Application, focus: Focus) bool {
        return self.collapsed[focus_index(focus)];
    }

    fn toggle_focused_section(self: *Application) void {
        const index = focus_index(self.focus);
        self.collapsed[index] = !self.collapsed[index];
        self.reader_only = false;
    }

    fn move_focused(self: *Application, delta: i16) bool {
        if (self.is_collapsed(self.focus)) return true;
        switch (self.focus) {
            .categories => self.move_categories(delta),
            .feeds => self.move_feeds(delta),
            .articles => self.move_articles(delta),
            .reader => self.move_reader(delta),
        }
        return true;
    }

    fn move_page(self: *Application, direction: i16) void {
        const rows = switch (self.focus) {
            .categories => self.category_viewport,
            .feeds => self.feed_viewport,
            .articles => self.article_viewport,
            .reader => self.reader_viewport,
        };
        _ = self.move_focused(direction * @as(i16, @intCast(@max(rows, 1))));
    }

    fn move_to_edge(self: *Application, last: bool) bool {
        switch (self.focus) {
            .categories => {
                self.category_cursor = if (last) self.category_count + 1 else 0;
                self.apply_category_cursor();
            },
            .feeds => {
                self.feed_cursor = if (last) self.filtered_feed_count else 0;
                self.apply_feed_cursor();
            },
            .articles => {
                self.article_cursor = if (last and self.filtered_article_count > 0)
                    self.filtered_article_count - 1
                else
                    0;
                self.ensure_article_visible();
            },
            .reader => {
                self.reader_scroll = if (last)
                    self.reader_line_count -| self.reader_viewport
                else
                    0;
            },
        }
        return true;
    }

    fn move_categories(self: *Application, delta: i16) void {
        self.category_cursor = move_index(
            self.category_cursor,
            self.category_count + 2,
            delta,
        );
        self.apply_category_cursor();
        ensure_visible(
            self.category_cursor,
            &self.category_scroll,
            self.category_viewport,
        );
    }

    fn move_feeds(self: *Application, delta: i16) void {
        self.feed_cursor = move_index(self.feed_cursor, self.filtered_feed_count + 1, delta);
        self.apply_feed_cursor();
        self.ensure_feed_visible();
    }

    fn move_articles(self: *Application, delta: i16) void {
        self.article_cursor = move_index(
            self.article_cursor,
            self.filtered_article_count,
            delta,
        );
        self.reader_scroll = 0;
        self.ensure_article_visible();
    }

    fn move_reader(self: *Application, delta: i16) void {
        const maximum = self.reader_line_count -| self.reader_viewport;
        self.reader_scroll = move_index_clamped(self.reader_scroll, maximum +| 1, delta);
    }

    pub fn set_category_viewport(self: *Application, rows: u16) void {
        self.category_viewport = @max(rows, 1);
        ensure_visible(self.category_cursor, &self.category_scroll, self.category_viewport);
    }

    pub fn set_feed_viewport(self: *Application, rows: u16) void {
        self.feed_viewport = @max(rows, 1);
        self.ensure_feed_visible();
    }

    pub fn set_article_viewport(self: *Application, rows: u16) void {
        self.article_viewport = @max(rows, 1);
        self.ensure_article_visible();
    }

    pub fn set_reader_metrics(self: *Application, lines: u16, rows: u16) void {
        self.reader_line_count = lines;
        self.reader_viewport = @max(rows, 1);
        self.reader_scroll = @min(self.reader_scroll, lines -| self.reader_viewport);
    }

    fn ensure_feed_visible(self: *Application) void {
        ensure_visible(self.feed_cursor, &self.feed_scroll, self.feed_viewport);
    }

    fn ensure_article_visible(self: *Application) void {
        ensure_visible(self.article_cursor, &self.article_scroll, self.article_viewport);
    }

    fn set_message(self: *Application, value: []const u8) !void {
        try self.message.set(value);
    }
};

fn move_index(index: u16, count: u16, delta: i16) u16 {
    if (count == 0) return 0;
    return move_index_clamped(index, count, delta);
}

fn move_index_clamped(index: u16, count: u16, delta: i16) u16 {
    if (count == 0) return 0;
    const maximum: i32 = count - 1;
    const moved = @as(i32, index) + delta;
    return @intCast(std.math.clamp(moved, 0, maximum));
}

fn ensure_visible(selected: u16, scroll: *u16, viewport: u16) void {
    std.debug.assert(viewport > 0);
    if (selected < scroll.*) scroll.* = selected;
    if (selected >= scroll.* +| viewport) scroll.* = selected - viewport + 1;
}

fn focus_index(focus: Focus) u8 {
    return @intCast(@backingInt(focus));
}

fn valid_http_url(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "https://") or
        std.mem.startsWith(u8, url, "http://");
}

fn fetch_task(
    io: std.Io,
    fetcher: *fetcher_module.Fetcher,
    client: *std.http.Client,
    results: *FetchResultQueue,
    worker_index: u16,
    feed_index: u16,
    url: model.FeedUrl,
) std.Io.Cancelable!void {
    const outcome: FetchOutcome = if (fetcher.fetch(client, url.bytes(), feed_index)) |update|
        .{ .update = update }
    else |err|
        .{ .failure = err };
    results.putOne(io, .{
        .worker_index = worker_index,
        .feed_index = feed_index,
        .outcome = outcome,
    }) catch |err| switch (err) {
        error.Closed => return,
        error.Canceled => return error.Canceled,
    };
}

test "filters honor category, feed, unread, and search scopes" {
    const application = try Application.create(
        std.testing.allocator,
        std.testing.io,
        "/tmp",
    );
    defer application.destroy(std.testing.allocator);
    application.feed_count = 2;
    application.feeds[0] = .{
        .title = try model.FeedTitle.init("Systems"),
        .url = try model.FeedUrl.init("https://one.test/rss"),
        .category = try model.CategoryName.init("Tech"),
    };
    application.feeds[1] = .{
        .title = try model.FeedTitle.init("Ideas"),
        .url = try model.FeedUrl.init("https://two.test/rss"),
        .category = try model.CategoryName.init("Context"),
    };
    application.article_count = 2;
    application.articles[0] = .{
        .title = try model.ArticleTitle.init("Zig release"),
        .url = try model.ArticleUrl.init("https://one.test/zig"),
        .feed_index = 0,
        .published_timestamp = 100,
    };
    application.articles[1] = .{
        .title = try model.ArticleTitle.init("A long essay"),
        .url = try model.ArticleUrl.init("https://two.test/essay"),
        .feed_index = 1,
        .published_timestamp = 200,
        .read = true,
    };
    application.rebuild_categories();
    _ = try application.handle_key(.{ .character = '?' });
    try std.testing.expect(application.help_open);
    _ = try application.handle_key(.{ .character = '?' });
    try std.testing.expect(!application.help_open);
    application.select_scope(.all, "");
    try std.testing.expectEqual(@as(u16, 1), application.filtered_articles[0]);
    application.focus = .articles;
    _ = try application.handle_character('c');
    try std.testing.expect(application.is_collapsed(.articles));
    _ = try application.handle_character('c');
    try std.testing.expect(!application.is_collapsed(.articles));
    _ = try application.handle_character('v');
    try std.testing.expect(application.reader_only);
    try std.testing.expectEqual(Focus.reader, application.focus);
    _ = try application.handle_key(.escape);
    try std.testing.expect(!application.reader_only);
    application.select_scope(.category, "Tech");
    try std.testing.expectEqual(@as(u16, 1), application.filtered_article_count);
    application.select_scope(.unread, "");
    try std.testing.expectEqual(@as(u16, 1), application.filtered_article_count);
    _ = try application.search.handle(.{ .character = 'Z' });
    application.refresh_articles();
    try std.testing.expectEqual(@as(u16, 1), application.filtered_article_count);
}
