const std = @import("std");

const SourceFile = struct {
    name: []const u8,
    source: [:0]const u8,
    reusable: bool = false,
};

const source_files = [_]SourceFile{
    source("src/app/application.zig", "app/application.zig", false),
    source("src/app/bookmarks.zig", "app/bookmarks.zig", false),
    source("src/app/bookmarks/bookmark.zig", "app/bookmarks/bookmark.zig", false),
    source("src/app/bookmarks/browser.zig", "app/bookmarks/browser.zig", false),
    source("src/app/bookmarks/fixed_text.zig", "app/bookmarks/fixed_text.zig", false),
    source("src/app/bookmarks/persistence.zig", "app/bookmarks/persistence.zig", false),
    source("src/app/bookmarks/store.zig", "app/bookmarks/store.zig", false),
    source("src/app/limits.zig", "app/limits.zig", false),
    source("src/app/page.zig", "app/page.zig", false),
    source("src/app/theme.zig", "app/theme.zig", false),
    source("src/app/view.zig", "app/view.zig", false),
    source("src/backend/terminal.zig", "backend/terminal.zig", true),
    source("src/backend/terminal/canvas.zig", "backend/terminal/canvas.zig", true),
    source("src/backend/terminal/event.zig", "backend/terminal/event.zig", true),
    source("src/backend/terminal/image.zig", "backend/terminal/image.zig", true),
    source("src/backend/terminal/input.zig", "backend/terminal/input.zig", true),
    source("src/backend/terminal/limits.zig", "backend/terminal/limits.zig", true),
    source("src/backend/terminal/sixel.zig", "backend/terminal/sixel.zig", true),
    source("src/backend/terminal/surface.zig", "backend/terminal/surface.zig", true),
    source("src/backend/terminal/terminal.zig", "backend/terminal/terminal.zig", true),
    source("src/backend/terminal/text_entry.zig", "backend/terminal/text_entry.zig", true),
    source(
        "src/backend/terminal/widgets/image.zig",
        "backend/terminal/widgets/image.zig",
        true,
    ),
    source(
        "src/backend/terminal/widgets/label.zig",
        "backend/terminal/widgets/label.zig",
        true,
    ),
    source(
        "src/backend/terminal/widgets/list.zig",
        "backend/terminal/widgets/list.zig",
        true,
    ),
    source(
        "src/backend/terminal/widgets/panel.zig",
        "backend/terminal/widgets/panel.zig",
        true,
    ),
    source(
        "src/backend/terminal/widgets/status_line.zig",
        "backend/terminal/widgets/status_line.zig",
        true,
    ),
    source(
        "src/backend/terminal/widgets/text_input.zig",
        "backend/terminal/widgets/text_input.zig",
        true,
    ),
    source("src/framework.zig", "framework.zig", true),
    source("src/framework/input.zig", "framework/input.zig", true),
    source("src/framework/limits.zig", "framework/limits.zig", true),
    source("src/framework/layout/color.zig", "framework/layout/color.zig", true),
    source("src/framework/layout/flex.zig", "framework/layout/flex.zig", true),
    source("src/framework/layout/grid.zig", "framework/layout/grid.zig", true),
    source("src/framework/layout/rect.zig", "framework/layout/rect.zig", true),
    source("src/framework/layout/tree.zig", "framework/layout/tree.zig", true),
    source("src/framework/style.zig", "framework/style.zig", true),
    source(
        "src/framework/widgets/text_input.zig",
        "framework/widgets/text_input.zig",
        true,
    ),
    source("src/main.zig", "main.zig", false),
    source("src/parser/document.zig", "parser/document.zig", true),
    source("src/parser/readable.zig", "parser/readable.zig", true),
    source("src/parser/xml.zig", "parser/xml.zig", true),
    source("src/rss/article_loader.zig", "rss/article_loader.zig", false),
    source("src/rss/application.zig", "rss/application.zig", false),
    source("src/rss/cache.zig", "rss/cache.zig", false),
    source("src/rss/date.zig", "rss/date.zig", false),
    source("src/rss/fetcher.zig", "rss/fetcher.zig", false),
    source("src/rss/image_loader.zig", "rss/image_loader.zig", false),
    source("src/rss/limits.zig", "rss/limits.zig", false),
    source("src/rss/model.zig", "rss/model.zig", false),
    source("src/rss/parser.zig", "rss/parser.zig", false),
    source("src/rss/state.zig", "rss/state.zig", false),
    source("src/rss/subscriptions.zig", "rss/subscriptions.zig", false),
    source("src/rss/view.zig", "rss/view.zig", false),
    source("src/rss_main.zig", "rss_main.zig", false),
    source("src/style_test.zig", "style_test.zig", false),
    source("src/tests.zig", "tests.zig", false),
};

fn source(
    comptime name: []const u8,
    comptime path: []const u8,
    comptime reusable: bool,
) SourceFile {
    return .{ .name = name, .source = @embedFile(path), .reusable = reusable };
}

test "source lines do not exceed 100 columns" {
    for (source_files) |file| {
        var lines = std.mem.splitScalar(u8, file.source, '\n');
        var line_number: u32 = 1;
        while (lines.next()) |line| : (line_number += 1) {
            if (line.len > 100) {
                std.debug.print(
                    "{s}:{d}: line has {d} columns\n",
                    .{ file.name, line_number, line.len },
                );
                return error.LineTooLong;
            }
        }
    }
}

test "functions do not exceed 70 lines" {
    for (source_files) |file| {
        var ast = try std.zig.Ast.parse(
            std.testing.allocator,
            file.source,
            .{ .mode = .zig },
        );
        defer ast.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 0), ast.errors.len);

        const tags = ast.nodes.items(.tag);
        for (tags, 0..) |tag, node_raw| {
            if (tag != .fn_decl) continue;
            const node: std.zig.Ast.Node.Index = @fromBackingInt(@intCast(node_raw));
            const span = ast.nodeToSpan(node);
            const function_source = file.source[span.start..span.end];
            const line_count = std.mem.count(u8, function_source, "\n") + 1;
            if (line_count > 70) {
                const line = std.mem.count(u8, file.source[0..span.start], "\n") + 1;
                std.debug.print(
                    "{s}:{d}: function has {d} lines\n",
                    .{ file.name, line, line_count },
                );
                return error.FunctionTooLong;
            }
        }
    }
}

test "reusable layers have no application dependency" {
    for (source_files) |file| {
        if (!file.reusable) continue;
        if (std.mem.indexOf(u8, file.source, "@import(\"../app") != null or
            std.mem.indexOf(u8, file.source, "@import(\"../../app") != null or
            std.mem.indexOf(u8, file.source, "@import(\"../../../app") != null)
        {
            std.debug.print("{s}: reusable layer imports application code\n", .{file.name});
            return error.ReusableLayerImportsApplication;
        }
        if (std.mem.startsWith(u8, file.name, "framework/") and
            std.mem.indexOf(u8, file.source, "backend/") != null)
        {
            std.debug.print("{s}: framework imports a backend\n", .{file.name});
            return error.FrameworkImportsBackend;
        }
    }
}
