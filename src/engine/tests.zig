const std = @import("std");
const mx = @import("../engine.zig");

const el = mx.dsl;
const Node = mx.Node;

fn options() mx.Options {
    return .{ .measure = mx.measure.monospace };
}

fn resolve_at(tree: *mx.Tree, width: i32) void {
    mx.resolve(tree, .{ .width = width, .height = mx.unbounded }, options());
}

test "a fixed row lays its children end to end" {
    var storage: [8]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.row(.{ .gap = 1, .width = .{ .fixed = 20 } }, .{
        el.text("ab", .{}),
        el.text("cde", .{}),
    }));
    resolve_at(&tree, 20);

    try std.testing.expectEqual(@as(i32, 0), tree.at(1).rect.x);
    try std.testing.expectEqual(@as(i32, 2), tree.at(1).rect.width);
    // One unit of gap, so the second run starts at 3, not 2.
    try std.testing.expectEqual(@as(i32, 3), tree.at(2).rect.x);
}

test "a column stacks and the parent fits the total" {
    var storage: [8]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.column(.{ .gap = 1 }, .{
        el.text("one", .{}),
        el.text("two", .{}),
    }));
    resolve_at(&tree, 40);

    try std.testing.expectEqual(@as(i32, 0), tree.at(1).rect.y);
    try std.testing.expectEqual(@as(i32, 2), tree.at(2).rect.y);
    try std.testing.expectEqual(@as(i32, 3), tree.at(0).rect.height);
}

test "padding insets children on every edge" {
    var storage: [4]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.column(.{ .padding = .{
        .left = 2,
        .right = 3,
        .top = 1,
        .bottom = 4,
    } }, .{el.text("x", .{})}));
    resolve_at(&tree, 40);

    try std.testing.expectEqual(@as(i32, 2), tree.at(1).rect.x);
    try std.testing.expectEqual(@as(i32, 1), tree.at(1).rect.y);
    try std.testing.expectEqual(@as(i32, 6), tree.at(0).rect.width);
    try std.testing.expectEqual(@as(i32, 6), tree.at(0).rect.height);
}

test "grow children split the remainder and leave nothing unused" {
    var storage: [8]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.row(.{ .width = .{ .fixed = 100 } }, .{
        el.spacer(.{}),
        el.spacer(.{}),
        el.spacer(.{}),
    }));
    resolve_at(&tree, 100);

    const total = tree.at(1).rect.width + tree.at(2).rect.width + tree.at(3).rect.width;
    try std.testing.expectEqual(@as(i32, 100), total);
    // The odd unit goes to the first rather than being lost to truncation.
    try std.testing.expectEqual(@as(i32, 34), tree.at(1).rect.width);
}

test "a spacer pushes a sibling to the far edge" {
    var storage: [8]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.row(.{ .width = .{ .fixed = 30 } }, .{
        el.text("left", .{}),
        el.spacer(.{}),
        el.text("right", .{}),
    }));
    resolve_at(&tree, 30);

    try std.testing.expectEqual(@as(i32, 0), tree.at(1).rect.x);
    try std.testing.expectEqual(@as(i32, 30), tree.at(3).rect.right());
}

test "text wraps into the width the grow pass settled" {
    var storage: [4]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.column(.{ .width = .{ .fixed = 10 } }, .{
        el.paragraph("the quick brown fox", .{ .width = .{ .grow = .{} } }),
    }));
    resolve_at(&tree, 10);

    // "the quick" / "brown fox" two rows at a measure of ten.
    try std.testing.expectEqual(@as(i32, 10), tree.at(1).rect.width);
    try std.testing.expectEqual(@as(i32, 2), tree.at(1).rect.height);
}

test "the same tree at a narrower measure is taller" {
    const view = el.column(.{ .width = .{ .grow = .{} } }, .{
        el.paragraph(
            "the quick brown fox jumps over the lazy dog",
            .{ .width = .{ .grow = .{} } },
        ),
    });

    var wide_storage: [4]Node = undefined;
    var wide = mx.Tree.init(&wide_storage);
    try el.mount(&wide, view);
    resolve_at(&wide, 40);

    var narrow_storage: [4]Node = undefined;
    var narrow = mx.Tree.init(&narrow_storage);
    try el.mount(&narrow, view);
    resolve_at(&narrow, 12);

    try std.testing.expect(narrow.at(0).rect.height > wide.at(0).rect.height);
}

test "inline children are one text stream, not several" {
    var storage: [8]Node = undefined;
    var tree = mx.Tree.init(&storage);
    // "see the manual now" eighteen columns, so it fits one row of twenty
    // and takes two at ten. A renderer that measured each piece on its own
    // would see three short runs and never wrap at all.
    try el.mount(&tree, el.column(.{ .width = .{ .fixed = 10 } }, .{
        el.rich(.{ .width = .{ .grow = .{} } }, .{
            el.run("see the ", .{}),
            el.link("manual", "/manual", .{}),
            el.run(" now", .{}),
        }),
    }));
    resolve_at(&tree, 10);

    try std.testing.expectEqual(@as(i32, 2), tree.at(1).rect.height);
}

test "a word split across inline runs is one word" {
    var storage: [8]Node = undefined;
    var tree = mx.Tree.init(&storage);
    // "abcde" and "fghij" abut with no space, so they are one ten-column
    // word and fit a measure of ten exactly. Measured as two separate runs
    // they would be two words needing eleven columns, and would wrap.
    try el.mount(&tree, el.column(.{ .width = .{ .fixed = 10 } }, .{
        el.rich(.{ .width = .{ .grow = .{} } }, .{
            el.run("abcde", .{}),
            el.strong("fghij", .{}),
        }),
    }));
    resolve_at(&tree, 10);

    try std.testing.expectEqual(@as(i32, 1), tree.at(1).rect.height);
}

test "inline boxes get no geometry of their own" {
    var storage: [8]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.column(.{ .width = .{ .fixed = 40 } }, .{
        el.rich(.{ .width = .{ .grow = .{} } }, .{
            el.link("a link", "/somewhere", .{}),
        }),
    }));
    resolve_at(&tree, 40);

    // The paragraph is placed; the link inside it is flowed.
    try std.testing.expect(tree.at(1).rect.width > 0);
    try std.testing.expectEqual(@as(i32, 0), tree.at(2).rect.width);
}

test "a code block keeps its own line breaks" {
    var storage: [4]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.column(.{ .width = .{ .fixed = 8 } }, .{
        el.code_block("one\ntwo\nthree and more", .{ .width = .{ .grow = .{} } }),
    }));
    resolve_at(&tree, 8);

    // Three authored lines, and the long one is not reflowed into four.
    try std.testing.expectEqual(@as(i32, 3), tree.at(1).rect.height);
}

test "alignment positions on both axes" {
    var storage: [4]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.row(.{
        .width = .{ .fixed = 20 },
        .height = .{ .fixed = 5 },
        .alignment = .{ .x = .center, .y = .center },
    }, .{el.text("ab", .{})}));
    mx.resolve(&tree, .{ .width = 20, .height = 5 }, options());

    try std.testing.expectEqual(@as(i32, 9), tree.at(1).rect.x);
    try std.testing.expectEqual(@as(i32, 2), tree.at(1).rect.y);
}

test "overflow shrinks what may shrink and respects a declared minimum" {
    var storage: [8]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.row(.{ .width = .{ .fixed = 10 } }, .{
        el.text("aaaaaaaa", .{ .width = .{ .fit = .{ .min = 6 } } }),
        el.text("bbbbbbbb", .{ .width = .{ .fit = .{ .min = 6 } } }),
    }));
    resolve_at(&tree, 10);

    // Sixteen units of content into ten. Neither child drops below the six it
    // declared, so the row overflows visibly instead of the text vanishing.
    try std.testing.expectEqual(@as(i32, 6), tree.at(1).rect.width);
    try std.testing.expectEqual(@as(i32, 6), tree.at(2).rect.width);
}

test "percent resolves against the parent's inner extent" {
    var storage: [4]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.column(.{
        .width = .{ .fixed = 40 },
        .padding = .symmetric(5, 0),
    }, .{el.column(.{ .width = .{ .percent = 50 } }, .{})}));
    resolve_at(&tree, 40);

    // Half of the thirty units inside the padding, not half of the forty.
    try std.testing.expectEqual(@as(i32, 15), tree.at(1).rect.width);
}

test "a hidden node and its subtree never reach the tree" {
    var storage: [8]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.column(.{}, .{
        el.text("shown", .{}),
        el.column(.{ .hidden = true }, .{
            el.text("gone", .{}),
            el.text("also gone", .{}),
        }),
    }));

    try std.testing.expectEqual(@as(u32, 2), tree.len);
    try std.testing.expectEqual(@as(u32, 1), tree.at(0).child_count);
}

test "declared chrome and looped content build one tree" {
    var storage: [16]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.column(.{ .width = .{ .fixed = 20 } }, .{
        el.text("header", .{}),
    }));
    const body = try el.mount_under(&tree, 0, el.column(.{
        .width = .{ .grow = .{} },
    }, .{}));
    for ([_][]const u8{ "one", "two", "three" }) |line| {
        _ = try el.mount_under(&tree, body, el.text(line, .{}));
    }
    resolve_at(&tree, 20);

    try std.testing.expectEqual(@as(u32, 6), tree.len);
    try std.testing.expectEqual(@as(u32, 3), tree.at(body).child_count);
    try std.testing.expectEqual(@as(i32, 4), tree.at(0).rect.height);
}

test "an empty tree resolves to nothing rather than trapping" {
    var storage: [4]Node = undefined;
    var tree = mx.Tree.init(&storage);
    mx.resolve(&tree, .{ .width = 40, .height = 10 }, options());
    try std.testing.expectEqual(@as(u32, 0), tree.len);
}

test "a zero-width measure neither divides by zero nor loops" {
    var storage: [4]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.column(.{ .width = .{ .fixed = 0 } }, .{
        el.paragraph("anything at all", .{ .width = .{ .grow = .{} } }),
    }));
    resolve_at(&tree, 0);
    try std.testing.expectEqual(@as(i32, 0), tree.at(1).rect.width);
}

// ---------------------------------------------------------------- rendering

fn render(
    buffer: []u8,
    tree: *mx.Tree,
) ![]const u8 {
    var writer = std.Io.Writer.fixed(buffer);
    const table = mx.html.StyleTable.collect(tree);
    try mx.html.write(&writer, tree, &table, .{});
    return writer.buffered();
}

test "one class per distinct style, however many boxes use it" {
    var storage: [8]Node = undefined;
    var tree = mx.Tree.init(&storage);
    const accent = mx.Style{ .foreground = mx.Color.rgb(0xc4a7e7), .bold = true };
    try el.mount(&tree, el.column(.{ .width = .{ .fixed = 40 } }, .{
        el.heading(2, "one", .{ .style = accent }),
        el.heading(2, "two", .{ .style = accent }),
        el.heading(2, "three", .{ .style = accent }),
    }));
    resolve_at(&tree, 40);

    const table = mx.html.StyleTable.collect(&tree);
    try std.testing.expectEqual(@as(usize, 1), table.len);

    var sheet: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&sheet);
    try mx.html.write_styles(&writer, &table, .{});
    try std.testing.expectEqualStrings(
        ".p .s0{color:#c4a7e7;font-weight:700}",
        writer.buffered(),
    );
}

test "markup refers to the sheet rather than repeating it" {
    var storage: [8]Node = undefined;
    var tree = mx.Tree.init(&storage);
    const accent = mx.Style{ .foreground = mx.Color.rgb(0xc4a7e7) };
    try el.mount(&tree, el.column(.{ .width = .{ .fixed = 40 } }, .{
        el.heading(2, "Title", .{ .style = accent, .id = "title" }),
    }));
    resolve_at(&tree, 40);

    var buffer: [1024]u8 = undefined;
    const output = try render(&buffer, &tree);
    try std.testing.expect(std.mem.indexOf(u8, output, "<h2 id=\"title\" class=\"s0\"") != null);
    // The colour is in the sheet, not on the element.
    try std.testing.expect(std.mem.indexOf(u8, output, "c4a7e7") == null);
}

test "an unstyled box carries no class at all" {
    var storage: [4]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.column(.{ .width = .{ .fixed = 10 } }, .{
        el.text("plain", .{}),
    }));
    resolve_at(&tree, 10);

    var buffer: [1024]u8 = undefined;
    const output = try render(&buffer, &tree);
    try std.testing.expect(std.mem.indexOf(u8, output, "class") == null);
}

test "inline elements are emitted without geometry" {
    var storage: [8]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.column(.{ .width = .{ .fixed = 40 } }, .{
        el.rich(.{ .width = .{ .grow = .{} } }, .{
            el.run("see ", .{}),
            el.link("the manual", "/manual", .{}),
        }),
    }));
    resolve_at(&tree, 40);

    var buffer: [1024]u8 = undefined;
    const output = try render(&buffer, &tree);
    try std.testing.expect(std.mem.indexOf(
        u8,
        output,
        "<a href=\"/manual\" class=\"x\">the manual</a>",
    ) != null);
    // The paragraph is positioned; the anchor inside it is not.
    try std.testing.expect(std.mem.indexOf(u8, output, "<p style=\"left:") != null);
}

test "padding is written out, not only reserved" {
    var storage: [4]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.column(.{ .width = .{ .fixed = 40 } }, .{
        el.heading(2, "Title", .{
            .width = .{ .grow = .{} },
            .padding = .{ .top = 1 },
        }),
    }));
    resolve_at(&tree, 40);

    var buffer: [1024]u8 = undefined;
    const output = try render(&buffer, &tree);
    // The box grew by a row; the browser has to know the row is above the
    // text rather than below it.
    try std.testing.expect(std.mem.indexOf(u8, output, "height:38px") != null);
    try std.testing.expect(
        std.mem.indexOf(u8, output, "padding:19px 0px 0px 0px") != null,
    );
}

test "a box with no padding says nothing about padding" {
    var storage: [4]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.column(.{ .width = .{ .fixed = 40 } }, .{
        el.text("plain", .{}),
    }));
    resolve_at(&tree, 40);

    var buffer: [1024]u8 = undefined;
    const output = try render(&buffer, &tree);
    try std.testing.expect(std.mem.indexOf(u8, output, "padding") == null);
}

test "headings resolve their level and text is escaped" {
    var storage: [4]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.column(.{ .width = .{ .fixed = 40 } }, .{
        el.heading(3, "a < b & c", .{}),
    }));
    resolve_at(&tree, 40);

    var buffer: [1024]u8 = undefined;
    const output = try render(&buffer, &tree);
    try std.testing.expect(std.mem.indexOf(u8, output, "<h3") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "a &lt; b &amp; c") != null);
}

test "void elements are not given a closing tag" {
    var storage: [4]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.column(.{ .width = .{ .fixed = 40 } }, .{
        el.image("/cat.png", "a cat", .{ .height = .{ .fixed = 8 } }),
    }));
    resolve_at(&tree, 40);

    var buffer: [1024]u8 = undefined;
    const output = try render(&buffer, &tree);
    try std.testing.expect(std.mem.indexOf(u8, output, "</img>") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "alt=\"a cat\"") != null);
}

test "the same style declaration drives both renderings" {
    // The property the old design could not hold: the wire format carried
    // colour and no attributes, so a bold heading rendered bold in the
    // generated document and lost its weight the instant the engine took over.
    // Here there is one declaration and both readers see all of it.
    const heading = mx.Style{ .foreground = mx.Color.rgb(0xc4a7e7), .bold = true };
    try std.testing.expect(heading.bold);
    try std.testing.expect(heading.foreground.is_set());

    var sheet: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&sheet);
    var table = mx.html.StyleTable{};
    table.entries[0] = heading;
    table.len = 1;
    try mx.html.write_styles(&writer, &table, .{});
    try std.testing.expect(
        std.mem.indexOf(u8, writer.buffered(), "font-weight:700") != null,
    );
}

test "horizontal geometry can be written in characters" {
    var storage: [8]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.row(.{ .gap = 1, .width = .{ .fixed = 20 } }, .{
        el.text("ab", .{}),
        el.text("cde", .{}),
    }));
    resolve_at(&tree, 20);

    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const table = mx.html.StyleTable.collect(&tree);
    try mx.html.write(&writer, &tree, &table, .{ .horizontal = .characters });
    const output = writer.buffered();

    // The second run starts three characters in, and is three wide. No pixel
    // advance is assumed anywhere, which is the point: a box is exactly as
    // wide as the characters standing in it.
    try std.testing.expect(std.mem.indexOf(u8, output, "left:3ch;top:0px;width:3ch") != null);
    // Vertical is still pixels: the line height is set exactly, so there is
    // nothing to guess about it.
    try std.testing.expect(std.mem.indexOf(u8, output, "height:19px") != null);
}

test "pixels remain the default" {
    var storage: [4]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.column(.{ .width = .{ .fixed = 4 } }, .{
        el.text("ab", .{}),
    }));
    resolve_at(&tree, 4);

    var buffer: [1024]u8 = undefined;
    const output = try render(&buffer, &tree);
    try std.testing.expect(std.mem.indexOf(u8, output, "width:36px") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "ch") == null);
}

test "a line can be worth more than one unit" {
    var storage: [8]Node = undefined;
    var tree = mx.Tree.init(&storage);
    // Two lines of text, each two units tall.
    try el.mount(&tree, el.column(.{ .width = .{ .fixed = 10 } }, .{
        el.heading(1, "the quick brown fox", .{
            .width = .{ .grow = .{} },
            .line_units = 2,
        }),
    }));
    resolve_at(&tree, 10);

    try std.testing.expectEqual(@as(i32, 4), tree.at(1).rect.height);
    try std.testing.expectEqual(@as(i32, 4), tree.at(0).rect.height);
}

test "one unit a line stays the default" {
    var storage: [8]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.column(.{ .width = .{ .fixed = 10 } }, .{
        el.paragraph("the quick brown fox", .{ .width = .{ .grow = .{} } }),
    }));
    resolve_at(&tree, 10);
    try std.testing.expectEqual(@as(i32, 2), tree.at(1).rect.height);
}

test "an external link opens in its own tab, safely" {
    var storage: [8]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.column(.{ .width = .{ .fixed = 40 } }, .{
        el.rich(.{ .width = .{ .grow = .{} } }, .{
            el.link("away", "https://example.com", .{ .external = true }),
            el.link("home", "/about", .{}),
        }),
    }));
    resolve_at(&tree, 40);

    var buffer: [1024]u8 = undefined;
    const output = try render(&buffer, &tree);
    try std.testing.expect(std.mem.indexOf(
        u8,
        output,
        "<a href=\"https://example.com\" target=_blank rel=noopener",
    ) != null);
    // An internal one stays where it is.
    try std.testing.expect(std.mem.indexOf(u8, output, "<a href=\"/about\" class") != null);
}

test "the semantic rendering is the document without the coordinates" {
    var storage: [16]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.column(.{ .width = .{ .fixed = 40 } }, .{
        el.heading(2, "A Heading", .{ .id = "a-heading" }),
        el.rich(.{ .width = .{ .grow = .{} } }, .{
            el.run("see ", .{}),
            el.link("the manual", "/manual", .{}),
            el.strong(" now", .{}),
        }),
    }));
    resolve_at(&tree, 40);

    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try mx.html.write_semantic(&writer, &tree, 0, .{});
    try std.testing.expectEqualStrings(
        "<div><h2 id=\"a-heading\">A Heading</h2>" ++
            "<p>see <a href=\"/manual\">the manual</a><b> now</b></p></div>",
        writer.buffered(),
    );
}

test "a semantic rendering can start below the root" {
    var storage: [16]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.column(.{ .width = .{ .fixed = 40 } }, .{
        el.text("chrome", .{}),
        el.column(.{ .element = .article }, .{
            el.paragraph("the article", .{}),
        }),
    }));
    resolve_at(&tree, 40);

    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    // Publishing an article without the page it happened to sit on.
    try mx.html.write_semantic(&writer, &tree, 2, .{});
    try std.testing.expectEqualStrings(
        "<article><p>the article</p></article>",
        writer.buffered(),
    );
}

test "syndicated markup can be made absolute" {
    var storage: [16]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.rich(.{ .width = .{ .fixed = 40 } }, .{
        el.link("here", "/posts/a/", .{}),
        el.link("away", "https://example.com/x", .{}),
        el.image("/cat.png", "a cat", .{}),
    }));
    resolve_at(&tree, 40);

    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try mx.html.write_semantic(&writer, &tree, 0, .{ .base = "https://site.example" });
    const output = writer.buffered();

    try std.testing.expect(
        std.mem.indexOf(u8, output, "href=\"https://site.example/posts/a/\"") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, output, "src=\"https://site.example/cat.png\"") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, output, "href=\"https://example.com/x\"") != null,
    );
}

test "a target cannot end a CDATA section" {
    var storage: [8]Node = undefined;
    var tree = mx.Tree.init(&storage);
    try el.mount(&tree, el.rich(.{ .width = .{ .fixed = 40 } }, .{
        el.link("odd", "/a]]>b", .{}),
    }));
    resolve_at(&tree, 40);

    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try mx.html.write_semantic(&writer, &tree, 0, .{});
    // Embedded in a feed, a literal one here would truncate the item.
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "]]>") == null);
}
