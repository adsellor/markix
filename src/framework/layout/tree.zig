const std = @import("std");
const flex_layout = @import("flex.zig");
const grid_layout = @import("grid.zig");
const limits = @import("../limits.zig");
const Rect = @import("rect.zig").Rect;

pub fn Tree(comptime Element: type) type {
    return struct {
        const Self = @This();
        pub const NodeIndex = u16;

        pub const Node = struct {
            element: Element,
            parent: ?Self.NodeIndex = null,
            first_child: ?Self.NodeIndex = null,
            last_child: ?Self.NodeIndex = null,
            next_sibling: ?Self.NodeIndex = null,
        };

        nodes: [limits.layout_nodes_max]Node = undefined,
        node_count: Self.NodeIndex = 0,
        root: ?Self.NodeIndex = null,

        pub fn init() Self {
            return .{};
        }

        pub fn reset(self: *Self) void {
            self.node_count = 0;
            self.root = null;
        }

        pub fn set_root(self: *Self, element: Element) !Self.NodeIndex {
            if (self.root != null) return error.RootAlreadySet;
            const index = try self.append_node(element, null);
            self.root = index;
            return index;
        }

        pub fn append_child(
            self: *Self,
            parent_index: Self.NodeIndex,
            element: Element,
        ) !Self.NodeIndex {
            if (parent_index >= self.node_count) return error.InvalidParent;
            const child_index = try self.append_node(element, parent_index);
            std.debug.assert(child_index > parent_index);
            const parent = &self.nodes[parent_index];
            if (parent.last_child) |last_child| {
                self.nodes[last_child].next_sibling = child_index;
            } else {
                parent.first_child = child_index;
            }
            parent.last_child = child_index;
            return child_index;
        }

        pub fn get(self: *Self, index: Self.NodeIndex) ?*Node {
            if (index >= self.node_count) return null;
            return &self.nodes[index];
        }

        pub fn child_count(
            self: *const Self,
            parent_index: Self.NodeIndex,
        ) Self.NodeIndex {
            if (parent_index >= self.node_count) return 0;
            var count: Self.NodeIndex = 0;
            var child = self.nodes[parent_index].first_child;
            while (child) |index| : (count += 1) {
                std.debug.assert(count < self.node_count);
                std.debug.assert(index < self.node_count);
                child = self.nodes[index].next_sibling;
            }
            return count;
        }

        fn append_node(
            self: *Self,
            element: Element,
            parent: ?Self.NodeIndex,
        ) !Self.NodeIndex {
            if (self.node_count >= limits.layout_nodes_max) return error.TreeFull;
            const index = self.node_count;
            self.nodes[index] = .{ .element = element, .parent = parent };
            self.node_count += 1;
            return index;
        }
    };
}

const FlexLayout = struct {
    direction: flex_layout.Direction,
    gap: u16,
    tracks: [limits.layout_items_max]flex_layout.Track = undefined,
    track_count: u8,
};

const GridLayout = struct {
    column_gap: u16,
    row_gap: u16,
    columns: [limits.layout_items_max]flex_layout.Track = undefined,
    column_count: u8,
    rows: [limits.layout_items_max]flex_layout.Track = undefined,
    row_count: u8,
};

pub const LayoutElement = struct {
    kind: union(enum) {
        leaf: void,
        flex: FlexLayout,
        grid: GridLayout,
    },
    rect: Rect = Rect.init(0, 0, 0, 0),

    pub fn leaf() LayoutElement {
        return .{ .kind = .{ .leaf = {} } };
    }

    pub fn flex(
        direction: flex_layout.Direction,
        gap: u16,
        tracks: []const flex_layout.Track,
    ) !LayoutElement {
        if (tracks.len == 0) return error.NoTracks;
        if (tracks.len > limits.layout_items_max) return error.TooManyTracks;
        var specification = FlexLayout{
            .direction = direction,
            .gap = gap,
            .track_count = @intCast(tracks.len),
        };
        @memcpy(specification.tracks[0..tracks.len], tracks);
        return .{ .kind = .{ .flex = specification } };
    }

    pub fn grid(
        column_gap: u16,
        row_gap: u16,
        columns: []const flex_layout.Track,
        rows: []const flex_layout.Track,
    ) !LayoutElement {
        if (columns.len == 0 or rows.len == 0) return error.NoTracks;
        if (columns.len > limits.layout_items_max) return error.TooManyTracks;
        if (rows.len > limits.layout_items_max) return error.TooManyTracks;
        const cell_count = std.math.mul(usize, columns.len, rows.len) catch
            return error.TooManyCells;
        if (cell_count > limits.layout_nodes_max - 1) return error.TooManyCells;
        var specification = GridLayout{
            .column_gap = column_gap,
            .row_gap = row_gap,
            .column_count = @intCast(columns.len),
            .row_count = @intCast(rows.len),
        };
        @memcpy(specification.columns[0..columns.len], columns);
        @memcpy(specification.rows[0..rows.len], rows);
        return .{ .kind = .{ .grid = specification } };
    }
};

pub const LayoutTree = Tree(LayoutElement);
pub const LayoutNodeIndex = LayoutTree.NodeIndex;

pub fn evaluate(tree: *LayoutTree, bounds: Rect) !void {
    const root_index = tree.root orelse return error.MissingRoot;
    std.debug.assert(root_index == 0);
    std.debug.assert(root_index < tree.node_count);
    tree.nodes[root_index].element.rect = bounds;
    var index: LayoutNodeIndex = 0;
    while (index < tree.node_count) : (index += 1) {
        const kind = tree.nodes[index].element.kind;
        switch (kind) {
            .leaf => if (tree.nodes[index].first_child != null) {
                return error.LeafHasChildren;
            },
            .flex => |specification| try evaluate_flex(tree, index, specification),
            .grid => |specification| try evaluate_grid(tree, index, specification),
        }
    }
}

fn evaluate_flex(
    tree: *LayoutTree,
    parent_index: LayoutNodeIndex,
    specification: FlexLayout,
) !void {
    const count = tree.child_count(parent_index);
    if (count != specification.track_count) return error.ChildTrackMismatch;
    var rectangles: [limits.layout_items_max]Rect = undefined;
    const parent = &tree.nodes[parent_index];
    try flex_layout.layout(
        parent.element.rect,
        specification.direction,
        specification.gap,
        specification.tracks[0..specification.track_count],
        rectangles[0..count],
    );
    assign_children(tree, parent_index, rectangles[0..count]);
}

fn evaluate_grid(
    tree: *LayoutTree,
    parent_index: LayoutNodeIndex,
    specification: GridLayout,
) !void {
    const count = tree.child_count(parent_index);
    const expected = @as(u16, specification.column_count) * specification.row_count;
    if (count != expected) return error.ChildTrackMismatch;
    var rectangles: [limits.layout_nodes_max]Rect = undefined;
    const parent = &tree.nodes[parent_index];
    try grid_layout.layout(
        parent.element.rect,
        specification.column_gap,
        specification.row_gap,
        specification.columns[0..specification.column_count],
        specification.rows[0..specification.row_count],
        rectangles[0..count],
    );
    assign_children(tree, parent_index, rectangles[0..count]);
}

fn assign_children(
    tree: *LayoutTree,
    parent_index: LayoutNodeIndex,
    rectangles: []const Rect,
) void {
    var child = tree.nodes[parent_index].first_child;
    var index: u16 = 0;
    while (child) |child_index| : (index += 1) {
        std.debug.assert(index < rectangles.len);
        std.debug.assert(child_index > parent_index);
        tree.nodes[child_index].element.rect = rectangles[index];
        child = tree.nodes[child_index].next_sibling;
    }
    std.debug.assert(index == rectangles.len);
}

test "layout tree evaluates nested flex and grid containers" {
    var tree = LayoutTree.init();
    const root = try tree.set_root(try LayoutElement.flex(
        .column,
        0,
        &.{ .{ .cells = 2 }, .{ .fraction = 1 } },
    ));
    _ = try tree.append_child(root, LayoutElement.leaf());
    const content = try tree.append_child(root, try LayoutElement.grid(
        1,
        0,
        &.{ .{ .fraction = 1 }, .{ .fraction = 1 } },
        &.{.{ .fraction = 1 }},
    ));
    const left = try tree.append_child(content, LayoutElement.leaf());
    const right = try tree.append_child(content, LayoutElement.leaf());
    try evaluate(&tree, Rect.init(0, 0, 21, 10));
    try std.testing.expectEqual(Rect.init(0, 2, 10, 8), tree.get(left).?.element.rect);
    try std.testing.expectEqual(Rect.init(11, 2, 10, 8), tree.get(right).?.element.rect);
}

test "layout tree rejects mismatched children and bounded overflow" {
    var tree = LayoutTree.init();
    const root = try tree.set_root(try LayoutElement.flex(
        .row,
        0,
        &.{.{ .fraction = 1 }},
    ));
    try std.testing.expectError(
        error.ChildTrackMismatch,
        evaluate(&tree, Rect.init(0, 0, 10, 2)),
    );
    _ = try tree.append_child(root, LayoutElement.leaf());
    while (tree.node_count < limits.layout_nodes_max) {
        _ = try tree.append_child(root, LayoutElement.leaf());
    }
    try std.testing.expectError(
        error.TreeFull,
        tree.append_child(root, LayoutElement.leaf()),
    );
}
