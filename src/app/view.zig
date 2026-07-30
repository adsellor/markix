const std = @import("std");
const terminal = @import("../backend/terminal.zig");
const framework = @import("../framework.zig");
const application_module = @import("application.zig");
const limits = @import("limits.zig");
const theme = @import("theme.zig");

const Rect = framework.Rect;
const Surface = terminal.Surface;
const ListItem = terminal.widgets.ListItem;
const LayoutNodeIndex = framework.layout_tree.LayoutNodeIndex;
const Span = terminal.widgets.Span;
const pane_chrome = terminal.widgets.PanelChrome{
    .rail_width = 1,
    .rail_height = 3,
    .content_padding_left = 1,
    .content_padding_top = 1,
    .header_background = false,
    .title_attributes = .{ .bold = true },
};
const bookmark_list_visual = terminal.widgets.ListVisual{
    .row_height = 2,
    .selected_marker = '>',
    .title_attributes = .{ .bold = true },
    .selected_attributes = .{ .bold = true },
    .subtitle_attributes = .{ .dim = true },
    .detail_width_divisor = 3,
};

pub fn render(application: anytype, canvas: *terminal.TerminalCanvas) !void {
    application.mouse_layout = .{};
    const surface = Surface{ .canvas = canvas };
    const bounds = surface.bounds();
    surface.fill(bounds, theme.background);
    var tree = framework.LayoutTree.init();
    const layout = try build_layout(&tree, bounds, application);
    try framework.layout_tree.evaluate(&tree, bounds);
    try draw_header(application, surface, node_rect(&tree, layout.header));
    const content = node_rect(&tree, layout.content);
    if (application.mode == .add) {
        try draw_add_form(application, surface, content);
    } else if (application.mode == .focus) {
        try draw_focus_mode(application, surface, content);
    } else {
        var slot_index: u8 = 0;
        while (slot_index < layout.slot_count) : (slot_index += 1) {
            const slot = layout.slots[slot_index];
            try draw_workspace_slot(
                application,
                surface,
                slot.kind,
                node_rect(&tree, slot.node),
            );
        }
    }
    try draw_status(application, surface, node_rect(&tree, layout.status));
}

const WorkspaceKind = enum { scopes, bookmarks, preview };

const WorkspaceSlot = struct {
    kind: WorkspaceKind,
    node: LayoutNodeIndex,
};

const AppLayout = struct {
    header: LayoutNodeIndex,
    content: LayoutNodeIndex,
    status: LayoutNodeIndex,
    slots: [3]WorkspaceSlot = undefined,
    slot_count: u8 = 0,
};

fn build_layout(
    tree: *framework.LayoutTree,
    bounds: Rect,
    application: anytype,
) !AppLayout {
    const root = try tree.set_root(try framework.LayoutElement.flex(
        .column,
        0,
        &.{ .{ .cells = 2 }, .{ .fraction = 1 }, .{ .cells = 1 } },
    ));
    var result = AppLayout{
        .header = try tree.append_child(root, framework.LayoutElement.leaf()),
        .content = undefined,
        .status = undefined,
    };
    if (application.mode == .add or application.mode == .focus) {
        result.content = try tree.append_child(root, framework.LayoutElement.leaf());
    } else {
        try append_workspace(tree, root, bounds.width, application, &result);
    }
    result.status = try tree.append_child(root, framework.LayoutElement.leaf());
    return result;
}

fn append_workspace(
    tree: *framework.LayoutTree,
    root: LayoutNodeIndex,
    width: u16,
    application: anytype,
    result: *AppLayout,
) !void {
    if (width >= 110) {
        const tracks = [_]framework.flex.Track{
            .{ .cells = 20 },
            .{ .fraction = 2 },
            .{ .fraction = 3 },
        };
        try append_workspace_flex(
            tree,
            root,
            &tracks,
            &.{ .scopes, .bookmarks, .preview },
            result,
        );
        return;
    }
    if (width >= 76) {
        const first: WorkspaceKind = if (application.browser_focus == .scopes)
            .scopes
        else
            .bookmarks;
        try append_workspace_flex(
            tree,
            root,
            &.{ .{ .fraction = 2 }, .{ .fraction = 3 } },
            &.{ first, .preview },
            result,
        );
        return;
    }
    result.content = try tree.append_child(root, framework.LayoutElement.leaf());
    result.slots[0] = .{
        .kind = narrow_workspace_kind(application),
        .node = result.content,
    };
    result.slot_count = 1;
}

fn append_workspace_flex(
    tree: *framework.LayoutTree,
    root: LayoutNodeIndex,
    tracks: []const framework.flex.Track,
    kinds: []const WorkspaceKind,
    result: *AppLayout,
) !void {
    std.debug.assert(tracks.len == kinds.len);
    std.debug.assert(kinds.len <= result.slots.len);
    result.content = try tree.append_child(
        root,
        try framework.LayoutElement.flex(.row, 1, tracks),
    );
    for (kinds, 0..) |kind, index| {
        result.slots[index] = .{
            .kind = kind,
            .node = try tree.append_child(result.content, framework.LayoutElement.leaf()),
        };
    }
    result.slot_count = @intCast(kinds.len);
}

fn narrow_workspace_kind(application: anytype) WorkspaceKind {
    if (application.mode == .command) return .preview;
    return switch (application.browser_focus) {
        .scopes => .scopes,
        .bookmarks => if (application.narrow_preview) .preview else .bookmarks,
        .preview => .preview,
    };
}

fn node_rect(tree: *framework.LayoutTree, node: LayoutNodeIndex) Rect {
    return tree.get(node).?.element.rect;
}

fn draw_header(application: anytype, surface: Surface, rect: Rect) !void {
    surface.fill(rect, theme.panel);
    _ = try terminal.widgets.Inline.draw(surface, rect, &.{
        .{
            .text = " MARKIX ",
            .foreground = theme.inverse_foreground,
            .background = theme.accent,
            .attributes = .{ .bold = true },
        },
        .{
            .text = "  LIBRARY",
            .foreground = theme.muted,
            .attributes = .{ .bold = true },
        },
    });
    var count_buffer: [32]u8 = undefined;
    const count = try std.fmt.bufPrint(
        &count_buffer,
        " {d} SAVED  {d} SHOWN ",
        .{ application.store.count, application.filtered_count },
    );
    if (count.len < rect.width) {
        try surface.text(
            rect.right() - @as(u16, @intCast(count.len)),
            rect.y,
            count,
            theme.muted,
            theme.panel_alt,
        );
    }
    const second_row = Rect.init(rect.x, rect.y +| 1, rect.width, 1);
    if (application.mode == .search) {
        try terminal.widgets.draw_text_input(
            &application.search,
            surface,
            second_row,
            .{
                .prompt = " SEARCH ",
                .placeholder = "title, URL, tag, note, or page text",
                .style = theme.focused_field,
                .focused = true,
            },
        );
    } else if (application.mode == .focus) {
        try draw_focus_header(application, surface, second_row);
    } else {
        try draw_breadcrumb(application, surface, second_row);
    }
}

fn draw_focus_header(application: anytype, surface: Surface, rect: Rect) !void {
    var count_buffer: [24]u8 = undefined;
    const count = std.fmt.bufPrint(
        &count_buffer,
        "{d} MATCHES",
        .{application.filtered_count},
    ) catch "";
    _ = try terminal.widgets.Inline.draw(surface, rect, &.{
        .{
            .text = " FOCUS ",
            .foreground = theme.inverse_foreground,
            .background = theme.accent_warm,
            .attributes = .{ .bold = true },
        },
        .{ .text = "  ", .foreground = theme.muted },
        .{
            .text = scope_name(application),
            .foreground = theme.foreground_strong,
            .attributes = .{ .bold = true },
        },
        .{ .text = "  /  ", .foreground = theme.line },
        .{
            .text = count,
            .foreground = theme.muted,
            .attributes = .{ .dim = true },
        },
    });
}

fn draw_breadcrumb(application: anytype, surface: Surface, rect: Rect) !void {
    const scope_width = try (terminal.widgets.Badge{
        .style = .{
            .foreground = theme.foreground_strong,
            .background = theme.panel_alt,
            .attributes = .{ .bold = true },
        },
    }).draw(surface, rect, scope_name(application));
    if (scope_width + 2 >= rect.width) return;
    _ = try (terminal.widgets.Segmented{
        .active_style = .{
            .foreground = focus_accent(application.browser_focus),
            .background = theme.background,
            .attributes = .{ .bold = true },
        },
        .idle_style = .{
            .foreground = theme.muted,
            .background = theme.panel,
            .attributes = .{ .dim = true },
        },
        .gap = 1,
    }).draw(
        surface,
        Rect.init(
            rect.x + scope_width + 2,
            rect.y,
            rect.width - scope_width - 2,
            1,
        ),
        &.{
            .{ .label = "Browse" },
            .{ .label = "Bookmarks" },
            .{ .label = "Preview" },
        },
        focus_index(application.browser_focus),
    );
}

fn focus_accent(focus: anytype) framework.Color {
    return switch (focus) {
        .scopes => theme.accent_cool,
        .bookmarks => theme.accent_warm,
        .preview => theme.accent,
    };
}

fn focus_index(focus: anytype) u16 {
    return switch (focus) {
        .scopes => 0,
        .bookmarks => 1,
        .preview => 2,
    };
}

fn scope_name(application: anytype) []const u8 {
    return switch (application.scope_kind) {
        .all => "All bookmarks",
        .favorites => "Favorites",
        .tag => application.active_tag.bytes(),
    };
}

fn draw_focus_mode(application: anytype, surface: Surface, rect: Rect) !void {
    surface.fill(rect, theme.background);
    if (!application.focus_search_open) {
        try draw_focus_bookmarks(application, surface, rect);
        return;
    }
    const finder = focus_finder_rect(rect);
    application.mouse_layout.focus_modal = finder;
    const occlusion = focus_finder_occlusion(rect, finder);
    const background_surface = surface.with_text_occlusion(&occlusion);
    try draw_focus_bookmarks(application, background_surface, rect);
    draw_focus_shadow(surface, rect, finder);
    try draw_focus_finder(application, surface, finder);
}

fn focus_finder_rect(bounds: Rect) Rect {
    const width_scaled = @divFloor(@as(u32, bounds.width) * 3, 4);
    const height_scaled = @divFloor(@as(u32, bounds.height) * 3, 4);
    const width = @min(@as(u16, @intCast(width_scaled)), 84);
    const height = @min(@as(u16, @intCast(height_scaled)), 17);
    return Rect.init(
        bounds.x + (bounds.width - width) / 2,
        bounds.y + (bounds.height - height) / 2,
        width,
        height,
    );
}

fn focus_finder_occlusion(bounds: Rect, finder: Rect) Rect {
    const width = finder.width +
        @intFromBool(finder.right() < bounds.right());
    const height = finder.height +
        @intFromBool(finder.y + finder.height < bounds.y + bounds.height);
    return Rect.init(finder.x, finder.y, width, height);
}

fn draw_focus_shadow(surface: Surface, bounds: Rect, rect: Rect) void {
    if (rect.width == 0 or rect.height == 0) return;
    const shadow_x = rect.x +| 1;
    const shadow_y = rect.y +| 1;
    const shadow = Rect.init(
        shadow_x,
        shadow_y,
        @min(rect.width, bounds.right() -| shadow_x),
        @min(rect.height, bounds.y + bounds.height -| shadow_y),
    );
    surface.fill(shadow, theme.shadow);
}

fn draw_focus_bookmarks(application: anytype, surface: Surface, rect: Rect) !void {
    if (rect.width == 0 or rect.height == 0) return;
    var meta_buffer: [24]u8 = undefined;
    const position = if (application.filtered_count == 0) 0 else application.selected + 1;
    const meta = std.fmt.bufPrint(
        &meta_buffer,
        "{d}/{d}",
        .{ position, application.filtered_count },
    ) catch "";
    const inner = try (terminal.widgets.Panel{
        .title = "FOCUS LIBRARY",
        .meta = meta,
        .style = theme.pane_style(theme.accent_warm, true),
        .focused = true,
        .chrome = pane_chrome,
    }).draw(surface, rect);
    application.mouse_layout.focus = .{
        .rect = inner,
        .scroll = application.scroll,
        .row_height = bookmark_list_visual.row_height,
    };
    try surface.selectable(inner, theme.selection_bookmarks);
    var items: [limits.bookmark_count_max]ListItem = undefined;
    build_bookmark_items(application, &items);
    const list = terminal.widgets.List{
        .style = theme.pane_style(theme.accent_warm, true),
        .empty_text = empty_bookmark_text(application),
        .highlight_query = application.search.value(),
        .match_foreground = theme.command,
        .focused = true,
        .visual = bookmark_list_visual,
    };
    application.set_viewport_rows(list.capacity(inner.height));
    try list.draw(
        surface,
        inner,
        items[0..application.filtered_count],
        application.selected,
        application.scroll,
    );
}

fn draw_focus_finder(application: anytype, surface: Surface, rect: Rect) !void {
    if (rect.width == 0 or rect.height == 0) return;
    const inner = try (terminal.widgets.Panel{
        .title = "FIND BOOKMARKS",
        .meta = scope_name(application),
        .style = theme.command_panel,
        .focused = true,
        .chrome = .{
            .rail_width = 1,
            .rail_height = 4,
            .content_padding_left = 2,
            .content_padding_top = 2,
            .header_background = true,
            .title_attributes = .{ .bold = true },
        },
    }).draw(surface, rect);
    if (inner.height == 0) return;
    try terminal.widgets.draw_text_input(
        &application.search,
        surface,
        Rect.init(inner.x, inner.y, inner.width, 1),
        .{
            .prompt = "/ ",
            .placeholder = "Fuzzy search titles, URLs, tags, notes, and page text",
            .style = theme.command_field,
            .focused = true,
        },
    );
    if (inner.height < 3) return;
    try draw_focus_categories(
        application,
        surface,
        Rect.init(inner.x, inner.y + 2, inner.width, 1),
    );
    if (inner.height <= 4) return;
    const results = Rect.init(
        inner.x,
        inner.y + 4,
        inner.width,
        inner.height - 4,
    );
    try draw_focus_finder_results(application, surface, results);
}

fn draw_focus_finder_results(
    application: anytype,
    surface: Surface,
    rect: Rect,
) !void {
    application.mouse_layout.finder_results = .{
        .rect = rect,
        .scroll = application.scroll,
        .row_height = bookmark_list_visual.row_height,
    };
    try surface.selectable(rect, theme.selection_command);
    var items: [limits.bookmark_count_max]ListItem = undefined;
    build_bookmark_items(application, &items);
    const list = terminal.widgets.List{
        .style = theme.command_panel,
        .empty_text = empty_bookmark_text(application),
        .highlight_query = application.search.value(),
        .match_foreground = theme.command,
        .focused = true,
        .visual = bookmark_list_visual,
    };
    application.set_viewport_rows(list.capacity(rect.height));
    try list.draw(
        surface,
        rect,
        items[0..application.filtered_count],
        application.selected,
        application.scroll,
    );
}

fn draw_focus_categories(application: anytype, surface: Surface, rect: Rect) !void {
    const label_width = try (terminal.widgets.Badge{ .style = .{
        .foreground = theme.inverse_foreground,
        .background = theme.accent_cool,
        .attributes = .{ .bold = true },
        .padding = 1,
    } }).draw(surface, rect, "FILTER");
    if (label_width + 1 >= rect.width) return;
    const categories = Rect.init(
        rect.x + label_width + 1,
        rect.y,
        rect.width - label_width - 1,
        1,
    );
    var items: [3]terminal.widgets.SegmentItem = undefined;
    var scope_indices: [3]u16 = undefined;
    const scope_count = application.tag_count + 2;
    const item_count = focus_category_items(
        application,
        &items,
        &scope_indices,
        scope_count,
    );
    const active_index: u16 = if (scope_count == 2) application.scope_cursor else 1;
    _ = try (terminal.widgets.Segmented{
        .active_style = .{
            .foreground = theme.inverse_foreground,
            .background = theme.command,
            .attributes = .{ .bold = true },
        },
        .idle_style = .{
            .foreground = theme.muted,
            .background = theme.command_panel.background,
            .attributes = .{ .dim = true },
        },
        .gap = 1,
    }).draw(surface, categories, items[0..item_count], active_index);
    register_focus_categories(
        application,
        categories,
        items[0..item_count],
        scope_indices[0..item_count],
    );
}

fn focus_category_items(
    application: anytype,
    items: *[3]terminal.widgets.SegmentItem,
    scope_indices: *[3]u16,
    scope_count: u16,
) u16 {
    if (scope_count == 2) {
        items[0] = .{ .label = scope_item_name(application, 0) };
        items[1] = .{ .label = scope_item_name(application, 1) };
        scope_indices[0] = 0;
        scope_indices[1] = 1;
        return 2;
    }
    const cursor = application.scope_cursor;
    const previous = if (cursor == 0) scope_count - 1 else cursor - 1;
    const next = if (cursor + 1 == scope_count) 0 else cursor + 1;
    items[0] = .{ .label = scope_item_name(application, previous) };
    items[1] = .{ .label = scope_item_name(application, cursor) };
    items[2] = .{ .label = scope_item_name(application, next) };
    scope_indices[0] = previous;
    scope_indices[1] = cursor;
    scope_indices[2] = next;
    return 3;
}

fn register_focus_categories(
    application: anytype,
    rect: Rect,
    items: []const terminal.widgets.SegmentItem,
    scope_indices: []const u16,
) void {
    std.debug.assert(items.len == scope_indices.len);
    std.debug.assert(items.len <= application.mouse_layout.categories.len);
    var column: u16 = 0;
    for (items, scope_indices, 0..) |item, scope_index, index| {
        if (column >= rect.width) break;
        const available = rect.width - column;
        const item_width = @min(
            @as(u16, @intCast(item.label.len + 2)),
            available,
        );
        application.mouse_layout.categories[index] = .{
            .rect = Rect.init(rect.x + column, rect.y, item_width, 1),
            .scope_index = scope_index,
        };
        application.mouse_layout.category_count += 1;
        column += item_width;
        if (column < rect.width) column += 1;
    }
}

fn draw_workspace_slot(
    application: anytype,
    surface: Surface,
    kind: WorkspaceKind,
    rect: Rect,
) !void {
    switch (kind) {
        .scopes => try draw_scopes(application, surface, rect),
        .bookmarks => try draw_bookmarks(application, surface, rect),
        .preview => if (application.mode == .command)
            try draw_command_deck(application, surface, rect)
        else
            try draw_preview(application, surface, rect),
    }
}

fn draw_command_deck(application: anytype, surface: Surface, rect: Rect) !void {
    var meta_buffer: [24]u8 = undefined;
    const meta = std.fmt.bufPrint(
        &meta_buffer,
        "{d} RESULTS",
        .{application.command_result_count},
    ) catch "";
    const inner = try (terminal.widgets.Panel{
        .title = "COMMAND DECK",
        .meta = meta,
        .style = theme.command_panel,
        .focused = true,
        .chrome = .{
            .rail_width = 1,
            .rail_height = 4,
            .content_padding_left = 2,
            .content_padding_top = 2,
            .header_background = true,
            .title_attributes = .{ .bold = true },
        },
    }).draw(surface, rect);
    if (inner.height == 0) return;
    try terminal.widgets.draw_text_input(
        &application.command,
        surface,
        Rect.init(inner.x, inner.y, inner.width, 1),
        .{
            .prompt = ": ",
            .placeholder = "Find anything or run an action",
            .style = theme.command_field,
            .focused = true,
        },
    );
    if (inner.height <= 2) return;
    const results = Rect.init(
        inner.x,
        inner.y + 2,
        inner.width,
        inner.height - 2,
    );
    const viewport_rows = @max(@divFloor(results.height, 2), 1);
    application.set_command_viewport_rows(viewport_rows);
    try draw_command_results(application, surface, results, viewport_rows);
}

fn draw_command_results(
    application: anytype,
    surface: Surface,
    rect: Rect,
    viewport_rows: u16,
) !void {
    application.mouse_layout.command_results = .{
        .rect = rect,
        .scroll = application.command_scroll,
        .row_height = 2,
    };
    if (application.command_result_count == 0) {
        try surface.styled_text_in(rect, 0, "No matching commands, bookmarks, or tags", .{
            .foreground = theme.muted,
            .background = theme.command_panel.background,
            .attributes = .{ .dim = true },
        });
        return;
    }
    var visible_index: u16 = 0;
    while (visible_index < viewport_rows) : (visible_index += 1) {
        const result_index = application.command_scroll + visible_index;
        if (result_index >= application.command_result_count) break;
        const row = Rect.init(
            rect.x,
            rect.y + visible_index * 2,
            rect.width,
            @min(@as(u16, 2), rect.height - visible_index * 2),
        );
        try draw_command_result(
            application,
            surface,
            row,
            application.command_results[result_index],
            result_index == application.command_selected,
        );
    }
}

fn draw_command_result(
    application: anytype,
    surface: Surface,
    rect: Rect,
    result: application_module.CommandResult,
    selected: bool,
) !void {
    if (rect.width < 6 or rect.height == 0) return;
    const accent_color = command_result_color(result);
    const marker = if (selected) ">" else " ";
    try surface.text(
        rect.x,
        rect.y,
        marker,
        accent_color,
        theme.command_panel.background,
    );
    _ = try (terminal.widgets.Badge{ .style = .{
        .foreground = theme.inverse_foreground,
        .background = accent_color,
        .attributes = .{ .bold = true },
        .padding = 0,
    } }).draw(
        surface,
        Rect.init(rect.x + 2, rect.y, 2, 1),
        command_result_kind(result),
    );
    try draw_command_result_text(application, surface, rect, result, selected);
}

fn draw_command_result_text(
    application: anytype,
    surface: Surface,
    rect: Rect,
    result: application_module.CommandResult,
    selected: bool,
) !void {
    const text_rect = Rect.init(rect.x + 5, rect.y, rect.width - 5, 1);
    const background = if (selected)
        theme.command_panel.selected_background
    else
        theme.command_panel.background;
    try (terminal.widgets.FuzzyText{
        .query = application.command.value(),
        .style = .{
            .foreground = if (selected) theme.foreground_strong else theme.foreground,
            .background = background,
            .attributes = .{ .bold = selected },
        },
        .match_style = .{
            .foreground = theme.command,
            .background = background,
            .attributes = .{ .bold = true, .underline = true },
        },
    }).draw(surface, text_rect, command_result_title(application, result));
    if (rect.height < 2) return;
    try surface.styled_text_in(
        Rect.init(text_rect.x, text_rect.y + 1, text_rect.width, 1),
        0,
        command_result_detail(application, result),
        .{
            .foreground = theme.muted,
            .background = background,
            .attributes = .{ .dim = true },
        },
    );
}

fn command_result_title(
    application: anytype,
    result: application_module.CommandResult,
) []const u8 {
    return switch (result) {
        .action => |action| application_module.command_action_label(action),
        .bookmark => |index| if (index < application.store.count)
            application.store.items[index].title.bytes()
        else
            "Unavailable bookmark",
        .tag => |index| if (index < application.tag_count)
            application.tags_available[index].bytes()
        else
            "Unavailable tag",
    };
}

fn command_result_detail(
    application: anytype,
    result: application_module.CommandResult,
) []const u8 {
    return switch (result) {
        .action => |action| application_module.command_action_detail(action),
        .bookmark => |index| if (index < application.store.count)
            application.store.items[index].host()
        else
            "",
        .tag => "Open this tag as a focused collection",
    };
}

fn command_result_kind(result: application_module.CommandResult) []const u8 {
    return switch (result) {
        .action => "DO",
        .bookmark => "BM",
        .tag => "##",
    };
}

fn command_result_color(result: application_module.CommandResult) framework.Color {
    return switch (result) {
        .action => theme.command,
        .bookmark => theme.accent_warm,
        .tag => theme.accent_cool,
    };
}

fn draw_scopes(application: anytype, surface: Surface, rect: Rect) !void {
    const focused = application.browser_focus == .scopes;
    var meta_buffer: [16]u8 = undefined;
    const meta = std.fmt.bufPrint(
        &meta_buffer,
        "{d} VIEWS",
        .{application.tag_count + 2},
    ) catch "";
    const inner = try (terminal.widgets.Panel{
        .title = "BROWSE",
        .meta = meta,
        .style = theme.pane_style(theme.accent_cool, focused),
        .focused = focused,
        .chrome = pane_chrome,
    }).draw(surface, rect);
    application.mouse_layout.scopes = .{
        .rect = inner,
        .scroll = application.scope_scroll,
        .row_height = 1,
    };
    try surface.selectable(inner, theme.selection_browse);
    const capacity = limits.tag_count_max + 2;
    var items: [capacity]ListItem = undefined;
    var counts: [capacity][8]u8 = undefined;
    var count_lengths: [capacity]u8 = undefined;
    const item_count = application.tag_count + 2;
    var index: u16 = 0;
    while (index < item_count) : (index += 1) {
        const count = scope_bookmark_count(application, index);
        const text = std.fmt.bufPrint(&counts[index], "{d}", .{count}) catch unreachable;
        count_lengths[index] = @intCast(text.len);
        items[index] = .{
            .title = scope_item_name(application, index),
            .detail = counts[index][0..count_lengths[index]],
            .marker = if (index < 2) ' ' else '#',
        };
    }
    application.set_scope_viewport_rows(inner.height);
    try (terminal.widgets.List{
        .style = theme.pane_style(theme.accent_cool, focused),
        .focused = focused,
        .visual = .{
            .row_height = 1,
            .selected_marker = '>',
            .detail_width_divisor = 3,
        },
    }).draw(
        surface,
        inner,
        items[0..item_count],
        application.scope_cursor,
        application.scope_scroll,
    );
}

fn scope_item_name(application: anytype, index: u16) []const u8 {
    if (index == 0) return "All";
    if (index == 1) return "Favorites";
    return application.tags_available[index - 2].bytes();
}

fn scope_bookmark_count(application: anytype, scope_index: u16) u16 {
    if (scope_index == 0) return application.store.count;
    var count: u16 = 0;
    var index: u16 = 0;
    while (index < application.store.count) : (index += 1) {
        const bookmark = &application.store.items[index];
        const matches = if (scope_index == 1)
            bookmark.favorite
        else
            bookmark.has_tag(application.tags_available[scope_index - 2].bytes());
        if (matches) count += 1;
    }
    return count;
}

fn draw_bookmarks(application: anytype, surface: Surface, rect: Rect) !void {
    const focused = application.browser_focus == .bookmarks;
    var meta_buffer: [20]u8 = undefined;
    const position = if (application.filtered_count == 0) 0 else application.selected + 1;
    const meta = std.fmt.bufPrint(
        &meta_buffer,
        "{d}/{d}",
        .{ position, application.filtered_count },
    ) catch "";
    const inner = try (terminal.widgets.Panel{
        .title = "BOOKMARKS",
        .meta = meta,
        .style = theme.pane_style(theme.accent_warm, focused),
        .focused = focused,
        .chrome = pane_chrome,
    }).draw(surface, rect);
    application.mouse_layout.bookmarks = .{
        .rect = inner,
        .scroll = application.scroll,
        .row_height = bookmark_list_visual.row_height,
    };
    try surface.selectable(inner, theme.selection_bookmarks);
    var items: [limits.bookmark_count_max]ListItem = undefined;
    build_bookmark_items(application, &items);
    const list = terminal.widgets.List{
        .style = theme.pane_style(theme.accent_warm, focused),
        .empty_text = empty_bookmark_text(application),
        .focused = focused,
        .visual = bookmark_list_visual,
    };
    application.set_viewport_rows(list.capacity(inner.height));
    try list.draw(
        surface,
        inner,
        items[0..application.filtered_count],
        application.selected,
        application.scroll,
    );
}

fn build_bookmark_items(
    application: anytype,
    items: *[limits.bookmark_count_max]ListItem,
) void {
    var index: u16 = 0;
    while (index < application.filtered_count) : (index += 1) {
        const bookmark = &application.store.items[application.filtered[index]];
        const host = bookmark.host();
        items[index] = .{
            .title = bookmark.title.bytes(),
            .detail = if (std.ascii.eqlIgnoreCase(bookmark.title.bytes(), host))
                ""
            else
                host,
            .subtitle = if (!bookmark.tags.is_empty())
                bookmark.tags.bytes()
            else
                bookmark.notes.bytes(),
            .marker = if (bookmark.favorite) '*' else ' ',
        };
    }
}

fn empty_bookmark_text(application: anytype) []const u8 {
    if (application.search.value().len > 0) return "No search results";
    if (application.scope_kind == .favorites) return "No favorites in this library";
    if (application.scope_kind == .tag) return "No bookmarks with this tag";
    return "Press a to add a bookmark";
}

fn draw_preview(application: anytype, surface: Surface, rect: Rect) !void {
    const focused = application.browser_focus == .preview;
    const inner = try (terminal.widgets.Panel{
        .title = "PREVIEW",
        .meta = "READER",
        .style = theme.pane_style(theme.accent, focused),
        .focused = focused,
        .chrome = pane_chrome,
    }).draw(surface, rect);
    application.mouse_layout.preview = inner;
    try surface.selectable(inner, theme.selection_preview);
    const bookmark = application.selected_bookmark() orelse {
        _ = try terminal.widgets.Inline.draw(surface, inner, &.{
            .{
                .text = " NO SELECTION ",
                .foreground = theme.muted,
                .background = theme.panel_alt,
            },
        });
        return;
    };
    var row = try draw_preview_heading(surface, inner, bookmark);
    row = try draw_preview_description(surface, inner, row, bookmark);
    try draw_preview_content(application, surface, inner, row, bookmark);
}

fn draw_preview_heading(surface: Surface, rect: Rect, bookmark: anytype) !u16 {
    var row: u16 = 0;
    if (row < rect.height) {
        try surface.styled_text_in(
            rect,
            row,
            bookmark.title.bytes(),
            .{
                .foreground = theme.foreground_strong,
                .background = theme.panel,
                .attributes = .{ .bold = true },
            },
        );
        row += 1;
    }
    row = try draw_labeled_row(
        surface,
        rect,
        row,
        " LINK ",
        theme.accent_cool,
        bookmark.url.bytes(),
        theme.muted,
        .{ .underline = true },
    );
    if (!bookmark.tags.is_empty()) {
        row = try draw_labeled_row(
            surface,
            rect,
            row,
            " TAGS ",
            theme.accent_warm,
            bookmark.tags.bytes(),
            theme.accent_warm,
            .{ .bold = true },
        );
    }
    if (!bookmark.notes.is_empty()) {
        row = try draw_labeled_row(
            surface,
            rect,
            row,
            " NOTE ",
            theme.accent,
            bookmark.notes.bytes(),
            theme.foreground,
            .{},
        );
    }
    return row +| @intFromBool(row < rect.height);
}

fn draw_preview_description(
    surface: Surface,
    rect: Rect,
    start_row: u16,
    bookmark: anytype,
) !u16 {
    if (bookmark.description.is_empty() or start_row >= rect.height) return start_row;
    var row = try draw_section_label(surface, rect, start_row, "SUMMARY");
    if (row >= rect.height) return row;
    const description_rect = Rect.init(
        rect.x,
        rect.y + row,
        rect.width,
        rect.height - row,
    );
    const used = try surface.wrapped_text(
        description_rect,
        bookmark.description.bytes(),
        theme.foreground,
        theme.panel,
    );
    row += used;
    return row +| @intFromBool(row < rect.height);
}

fn draw_preview_content(
    application: anytype,
    surface: Surface,
    rect: Rect,
    start_row: u16,
    bookmark: anytype,
) !void {
    if (start_row >= rect.height) return;
    const label = if (bookmark.preview.is_empty()) "NOT FETCHED" else "CONTENT";
    const scrollbar_visible = bookmark.preview.bytes().len > 0 and rect.width > 8;
    const scrollbar_width: u16 = if (scrollbar_visible) 2 else 0;
    const content_width = rect.width -| scrollbar_width;
    const line_count = wrapped_line_count(bookmark.preview.bytes(), content_width);
    var progress_buffer: [24]u8 = undefined;
    const progress = if (line_count == 0)
        ""
    else
        try std.fmt.bufPrint(
            &progress_buffer,
            " {d}/{d} ",
            .{ @min(application.preview_scroll +| 1, line_count), line_count },
        );
    const content_start = try draw_section_label(surface, rect, start_row, label);
    if (progress.len + label.len + 1 < rect.width) {
        try surface.text(
            rect.right() - @as(u16, @intCast(progress.len)),
            rect.y + start_row,
            progress,
            theme.accent,
            theme.panel_alt,
        );
    }
    if (content_start >= rect.height) return;
    const content_rect = Rect.init(
        rect.x,
        rect.y + content_start,
        content_width,
        rect.height - content_start,
    );
    application.set_preview_metrics(line_count, content_rect.height);
    try draw_wrapped_window(
        surface,
        content_rect,
        bookmark.preview.bytes(),
        application.preview_scroll,
    );
    if (scrollbar_visible) {
        try (terminal.widgets.Scrollbar{ .style = .{
            .track_foreground = theme.line,
            .track_background = theme.panel,
            .thumb_foreground = theme.accent,
            .thumb_background = theme.panel_alt,
            .track_character = '.',
            .thumb_character = '#',
        } }).draw(
            surface,
            Rect.init(rect.right() - 1, content_rect.y, 1, content_rect.height),
            application.preview_scroll,
            line_count,
            content_rect.height,
        );
    }
}

fn draw_labeled_row(
    surface: Surface,
    rect: Rect,
    row: u16,
    label: []const u8,
    label_color: framework.Color,
    value: []const u8,
    value_color: framework.Color,
    value_attributes: terminal.TextAttributes,
) !u16 {
    if (row >= rect.height) return row;
    _ = try terminal.widgets.Inline.draw(
        surface,
        Rect.init(rect.x, rect.y + row, rect.width, 1),
        &.{
            .{
                .text = label,
                .foreground = theme.inverse_foreground,
                .background = label_color,
            },
            .{ .text = " ", .foreground = theme.muted },
            .{
                .text = value,
                .foreground = value_color,
                .attributes = value_attributes,
            },
        },
    );
    return row + 1;
}

fn draw_section_label(
    surface: Surface,
    rect: Rect,
    row: u16,
    label: []const u8,
) !u16 {
    if (row >= rect.height) return row;
    _ = try terminal.widgets.Inline.draw(
        surface,
        Rect.init(rect.x, rect.y + row, rect.width, 1),
        &.{
            .{
                .text = label,
                .foreground = theme.muted,
                .background = theme.panel_alt,
            },
        },
    );
    return row + 1;
}

fn draw_wrapped_window(
    surface: Surface,
    rect: Rect,
    text: []const u8,
    skip_rows: u16,
) !void {
    if (rect.width == 0 or rect.height == 0) return;
    var offset: usize = 0;
    var logical_row: u16 = 0;
    var visible_row: u16 = 0;
    while (offset < text.len and visible_row < rect.height) {
        const line = next_wrapped_line(text, offset, rect.width);
        if (logical_row >= skip_rows) {
            try surface.text_in(
                rect,
                visible_row,
                text[line.start..line.end],
                theme.foreground,
                theme.panel,
            );
            visible_row += 1;
        }
        logical_row +|= 1;
        offset = line.next;
    }
}

const WrappedLine = struct { start: usize, end: usize, next: usize };

fn next_wrapped_line(text: []const u8, offset: usize, width: u16) WrappedLine {
    var start = offset;
    while (start < text.len and text[start] == ' ') start += 1;
    const maximum = @min(text.len, start + width);
    var end = maximum;
    if (maximum < text.len) {
        const space = std.mem.lastIndexOfScalar(u8, text[start..maximum], ' ');
        if (space) |index| {
            if (index > 0) end = start + index;
        }
    }
    var next = end;
    while (next < text.len and text[next] == ' ') next += 1;
    return .{ .start = start, .end = end, .next = next };
}

fn wrapped_line_count(text: []const u8, width: u16) u16 {
    if (width == 0) return 0;
    var count: u16 = 0;
    var offset: usize = 0;
    while (offset < text.len) {
        const line = next_wrapped_line(text, offset, width);
        if (line.next <= offset) break;
        offset = line.next;
        count +|= 1;
    }
    return count;
}

fn draw_add_form(application: anytype, surface: Surface, rect: Rect) !void {
    const width = @min(rect.width, 78);
    const height = @min(rect.height, 12);
    const form_rect = Rect.init(
        rect.x + (rect.width - width) / 2,
        rect.y + (rect.height - height) / 2,
        width,
        height,
    );
    const inner = try (terminal.widgets.Panel{
        .title = "NEW BOOKMARK",
        .style = theme.focused_panel,
        .focused = true,
        .chrome = .{
            .rail_width = 1,
            .rail_height = 0,
            .content_padding_left = 2,
            .content_padding_top = 2,
            .header_background = true,
            .title_attributes = .{ .bold = true },
        },
    }).draw(surface, form_rect);
    _ = try (terminal.widgets.Segmented{
        .active_style = .{
            .foreground = theme.inverse_foreground,
            .background = theme.accent_warm,
            .attributes = .{ .bold = true },
        },
        .idle_style = .{
            .foreground = theme.muted,
            .background = theme.panel_alt,
            .attributes = .{ .dim = true },
        },
        .gap = 1,
    }).draw(
        surface,
        inner,
        &.{
            .{ .label = "Title" },
            .{ .label = "URL" },
            .{ .label = "Tags" },
            .{ .label = "Note" },
        },
        field_index(application.field),
    );
    if (inner.height <= 2) return;
    const grid_rect = Rect.init(inner.x, inner.y + 2, inner.width, inner.height - 2);
    var tree = framework.LayoutTree.init();
    const root = try tree.set_root(try framework.LayoutElement.grid(
        1,
        1,
        &.{ .{ .cells = 8 }, .{ .fraction = 1 } },
        &.{
            .{ .cells = 1 },
            .{ .cells = 1 },
            .{ .cells = 1 },
            .{ .cells = 1 },
        },
    ));
    var nodes: [8]LayoutNodeIndex = undefined;
    for (&nodes) |*node| {
        node.* = try tree.append_child(root, framework.LayoutElement.leaf());
    }
    try framework.layout_tree.evaluate(&tree, grid_rect);
    var cells: [8]Rect = undefined;
    for (nodes, 0..) |node, index| cells[index] = node_rect(&tree, node);
    try draw_form_labels(surface, &cells);
    try draw_form_inputs(application, surface, &cells);
}

fn draw_form_labels(surface: Surface, cells: *const [8]Rect) !void {
    const labels = [_][]const u8{ "TITLE", "URL", "TAGS", "NOTE" };
    var row: usize = 0;
    while (row < labels.len) : (row += 1) {
        try (terminal.widgets.Label{
            .text = labels[row],
            .style = theme.panel_style,
            .muted = true,
        }).draw(surface, cells[row * 2]);
    }
}

fn draw_form_inputs(application: anytype, surface: Surface, cells: *const [8]Rect) !void {
    const fields = [_]application_module.Field{ .title, .url, .tags, .notes };
    var field_index_value: u8 = 0;
    while (field_index_value < fields.len) : (field_index_value += 1) {
        application.mouse_layout.fields[field_index_value] = .{
            .rect = cells[field_index_value * 2 + 1],
            .field = fields[field_index_value],
        };
    }
    application.mouse_layout.field_count = fields.len;
    try terminal.widgets.draw_text_input(
        &application.title,
        surface,
        cells[1],
        .{
            .placeholder = "Page title",
            .style = field_style(application.field == .title),
            .focused = application.field == .title,
        },
    );
    try terminal.widgets.draw_text_input(
        &application.url,
        surface,
        cells[3],
        .{
            .placeholder = "https://",
            .style = field_style(application.field == .url),
            .focused = application.field == .url,
        },
    );
    try terminal.widgets.draw_text_input(
        &application.tags,
        surface,
        cells[5],
        .{
            .placeholder = "design, systems, reading",
            .style = field_style(application.field == .tags),
            .focused = application.field == .tags,
        },
    );
    try terminal.widgets.draw_text_input(
        &application.notes,
        surface,
        cells[7],
        .{
            .placeholder = "Why this is worth keeping",
            .style = field_style(application.field == .notes),
            .focused = application.field == .notes,
        },
    );
}

fn field_style(focused: bool) framework.Style {
    return if (focused) theme.focused_field else theme.panel_style;
}

fn field_index(field: anytype) u16 {
    return switch (field) {
        .title => 0,
        .url => 1,
        .tags => 2,
        .notes => 3,
    };
}

fn draw_status(application: anytype, surface: Surface, rect: Rect) !void {
    const status = terminal.widgets.StatusLine{
        .style = if (application.mode == .confirm_delete) theme.warning else theme.base,
        .visual = .{
            .message_attributes = .{ .bold = true },
            .key_attributes = .{ .bold = true },
            .label_attributes = .{ .dim = true },
            .hint_gap = 2,
        },
    };
    switch (application.mode) {
        .browse, .confirm_delete => try status.draw(
            surface,
            rect,
            application.message.bytes(),
            &.{
                .{ .key = "h/l", .label = "focus" },
                .{ .key = "j/k", .label = "move" },
                .{ .key = "enter", .label = "open/apply" },
                .{ .key = "1/2", .label = "all/favorites" },
                .{ .key = "r", .label = "refresh" },
                .{ .key = "a", .label = "add" },
                .{ .key = "/", .label = "search" },
                .{ .key = ":", .label = "command" },
                .{ .key = "z", .label = "focus" },
                .{ .key = "q", .label = "quit" },
            },
        ),
        .search => try status.draw(surface, rect, "Search within the active scope", &.{
            .{ .key = "enter", .label = "keep" },
            .{ .key = "esc", .label = "clear" },
        }),
        .add => try status.draw(surface, rect, application.message.bytes(), &.{
            .{ .key = "tab", .label = "next field" },
            .{ .key = "enter", .label = "next/save" },
            .{ .key = "esc", .label = "cancel" },
        }),
        .command => try status.draw(surface, rect, "Command deck", &.{
            .{ .key = "type", .label = "fuzzy find" },
            .{ .key = "ctrl-n/p", .label = "move" },
            .{ .key = "enter", .label = "run" },
            .{ .key = "esc", .label = "close" },
        }),
        .focus => if (application.focus_search_open)
            try status.draw(surface, rect, "Telescope search", &.{
                .{ .key = "type", .label = "fuzzy find" },
                .{ .key = "tab", .label = "next category" },
                .{ .key = "ctrl-n/p", .label = "move" },
                .{ .key = "enter", .label = "apply" },
                .{ .key = "esc", .label = "clear" },
            })
        else
            try status.draw(surface, rect, application.message.bytes(), &.{
                .{ .key = "j/k", .label = "move" },
                .{ .key = "/", .label = "find" },
                .{ .key = "enter", .label = "open" },
                .{ .key = "f", .label = "favorite" },
                .{ .key = "z/q", .label = "workspace" },
            }),
    }
}

test "bookmark view renders scopes content and responsive layouts" {
    const Application = @import("application.zig").Application;
    const Bookmark = @import("bookmarks.zig").Bookmark;
    const application = try Application.create(
        std.testing.allocator,
        std.testing.io,
        "/tmp",
    );
    defer application.destroy(std.testing.allocator);
    var bookmark = try Bookmark.init("", "https://tigerbeetle.com", "systems", "Read later");
    try bookmark.preview.set("Reliable systems software with explicit operational limits.");
    try application.store.add(bookmark);
    application.rebuild_tags();
    application.filtered[0] = 0;
    application.filtered_count = 1;

    var canvas = try terminal.TerminalCanvas.init(std.testing.allocator, 120, 40);
    defer canvas.deinit();
    try render(application, &canvas);
    canvas.text_entries.clearRetainingCapacity();
    try canvas.resize(80, 20);
    try render(application, &canvas);
    canvas.text_entries.clearRetainingCapacity();
    try canvas.resize(40, 16);
    try render(application, &canvas);
}

test "command deck renders as a responsive sidecar" {
    const Application = @import("application.zig").Application;
    const Bookmark = @import("bookmarks.zig").Bookmark;
    const application = try Application.create(
        std.testing.allocator,
        std.testing.io,
        "/tmp",
    );
    defer application.destroy(std.testing.allocator);
    try application.store.add(
        try Bookmark.init("Tiger Style", "https://tigerbeetle.com", "systems", ""),
    );
    application.rebuild_tags();
    application.filtered[0] = 0;
    application.filtered_count = 1;
    _ = try application.handle_key(.{ .character = ':' });

    var canvas = try terminal.TerminalCanvas.init(std.testing.allocator, 120, 40);
    defer canvas.deinit();
    try render(application, &canvas);
    try std.testing.expect(canvas_has_text(&canvas, "COMMAND DECK"));
    canvas.text_entries.clearRetainingCapacity();
    try canvas.resize(80, 20);
    try render(application, &canvas);
    try std.testing.expect(canvas_has_text(&canvas, "COMMAND DECK"));
    canvas.text_entries.clearRetainingCapacity();
    try canvas.resize(40, 16);
    try render(application, &canvas);
    try std.testing.expect(canvas_has_text(&canvas, "COMMAND DECK"));
}

test "focus mode renders a list and responsive floating finder" {
    const Application = @import("application.zig").Application;
    const Bookmark = @import("bookmarks.zig").Bookmark;
    const application = try Application.create(
        std.testing.allocator,
        std.testing.io,
        "/tmp",
    );
    defer application.destroy(std.testing.allocator);
    try application.store.add(
        try Bookmark.init("Tiger Style", "https://tigerbeetle.com", "systems", ""),
    );
    application.rebuild_tags();
    application.filtered[0] = 0;
    application.filtered_count = 1;
    _ = try application.handle_key(.{ .character = 'z' });

    var focus_canvas = try terminal.TerminalCanvas.init(
        std.testing.allocator,
        120,
        40,
    );
    defer focus_canvas.deinit();
    try render(application, &focus_canvas);
    try std.testing.expect(canvas_has_text(&focus_canvas, "FOCUS LIBRARY"));
    try std.testing.expect(!canvas_has_text(&focus_canvas, "PREVIEW"));
    try std.testing.expect(application.mouse_layout.focus != null);

    _ = try application.handle_key(.{ .character = '/' });
    var finder_canvas = try terminal.TerminalCanvas.init(
        std.testing.allocator,
        80,
        24,
    );
    defer finder_canvas.deinit();
    try render(application, &finder_canvas);
    try std.testing.expect(canvas_has_text(&finder_canvas, "FIND BOOKMARKS"));
    try std.testing.expect(canvas_has_text(&finder_canvas, "FILTER"));
    try std.testing.expect(canvas_has_text(&finder_canvas, "FOCUS LIBRARY"));
    try std.testing.expect(application.mouse_layout.focus_modal != null);
    try std.testing.expect(application.mouse_layout.finder_results != null);
    try std.testing.expect(application.mouse_layout.category_count > 0);
    const finder = focus_finder_rect(Rect.init(0, 2, 80, 21));
    try std.testing.expect(canvas_has_text_in(&finder_canvas, "Tiger Style", finder));

    var narrow_canvas = try terminal.TerminalCanvas.init(
        std.testing.allocator,
        40,
        16,
    );
    defer narrow_canvas.deinit();
    try render(application, &narrow_canvas);
    try std.testing.expect(canvas_has_text(&narrow_canvas, "FIND BOOKMARKS"));
}

fn canvas_has_text(canvas: *const terminal.TerminalCanvas, text: []const u8) bool {
    for (canvas.text_entries.items) |entry| {
        if (std.mem.eql(u8, entry.bytes(), text)) return true;
    }
    return false;
}

fn canvas_has_text_in(
    canvas: *const terminal.TerminalCanvas,
    text: []const u8,
    rect: Rect,
) bool {
    for (canvas.text_entries.items) |entry| {
        if (!std.mem.eql(u8, entry.bytes(), text)) continue;
        if (entry.x < rect.x or entry.x >= rect.right()) continue;
        if (entry.y < rect.y or entry.y >= rect.y + rect.height) continue;
        return true;
    }
    return false;
}
