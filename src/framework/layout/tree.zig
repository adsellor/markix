const std = @import("std");
const limits = @import("../limits.zig");

pub fn Tree(comptime Element: type) type {
    return struct {
        const Self = @This();
        pub const NodeIndex = u16;

        pub const Node = struct {
            element: Element,
            parent: ?NodeIndex = null,
            first_child: ?NodeIndex = null,
            last_child: ?NodeIndex = null,
            next_sibling: ?NodeIndex = null,
        };

        allocator: std.mem.Allocator,
        nodes: []Node,
        node_count: NodeIndex = 0,
        root: ?NodeIndex = null,

        pub fn init(allocator: std.mem.Allocator) !Self {
            const nodes = try allocator.alloc(Node, limits.layout_nodes_max);
            return .{ .allocator = allocator, .nodes = nodes };
        }

        pub fn deinit(self: *Self) void {
            std.debug.assert(self.node_count <= self.nodes.len);
            self.allocator.free(self.nodes);
            self.nodes = &.{};
            self.node_count = 0;
            self.root = null;
        }

        pub fn set_root(self: *Self, element: Element) !NodeIndex {
            if (self.root != null) return error.RootAlreadySet;
            const index = try self.append_node(element, null);
            self.root = index;
            return index;
        }

        pub fn append_child(
            self: *Self,
            parent_index: NodeIndex,
            element: Element,
        ) !NodeIndex {
            if (parent_index >= self.node_count) return error.InvalidParent;
            const child_index = try self.append_node(element, parent_index);
            const parent = &self.nodes[parent_index];
            if (parent.last_child) |last_child| {
                self.nodes[last_child].next_sibling = child_index;
            } else {
                parent.first_child = child_index;
            }
            parent.last_child = child_index;
            return child_index;
        }

        pub fn get(self: *Self, index: NodeIndex) ?*Node {
            if (index >= self.node_count) return null;
            return &self.nodes[index];
        }

        pub fn child_count(self: *const Self, parent_index: NodeIndex) NodeIndex {
            if (parent_index >= self.node_count) return 0;
            var count: NodeIndex = 0;
            var child = self.nodes[parent_index].first_child;
            while (child) |index| : (count += 1) {
                std.debug.assert(index < self.node_count);
                child = self.nodes[index].next_sibling;
            }
            return count;
        }

        fn append_node(
            self: *Self,
            element: Element,
            parent: ?NodeIndex,
        ) !NodeIndex {
            if (self.node_count >= self.nodes.len) return error.TreeFull;
            const index = self.node_count;
            self.nodes[index] = .{ .element = element, .parent = parent };
            self.node_count += 1;
            return index;
        }
    };
}

test "layout tree stores backend-neutral elements with stable indexes" {
    const TestTree = Tree(u32);
    var tree = try TestTree.init(std.testing.allocator);
    defer tree.deinit();

    const root = try tree.set_root(10);
    const first = try tree.append_child(root, 20);
    const second = try tree.append_child(root, 30);

    try std.testing.expectEqual(@as(u16, 0), root);
    try std.testing.expectEqual(@as(u16, 1), first);
    try std.testing.expectEqual(@as(u16, 2), second);
    try std.testing.expectEqual(@as(u16, 2), tree.child_count(root));
    try std.testing.expectEqual(@as(u32, 30), tree.get(second).?.element);
}

test "layout tree rejects invalid parents and excess roots" {
    const TestTree = Tree(u8);
    var tree = try TestTree.init(std.testing.allocator);
    defer tree.deinit();

    _ = try tree.set_root(1);
    try std.testing.expectError(error.RootAlreadySet, tree.set_root(2));
    try std.testing.expectError(error.InvalidParent, tree.append_child(4, 3));
}

test "layout tree rejects nodes beyond fixed capacity" {
    const TestTree = Tree(void);
    var tree = try TestTree.init(std.testing.allocator);
    defer tree.deinit();

    const root = try tree.set_root({});
    while (tree.node_count < limits.layout_nodes_max) {
        _ = try tree.append_child(root, {});
    }
    try std.testing.expectError(error.TreeFull, tree.append_child(root, {}));
    try std.testing.expectEqual(limits.layout_nodes_max, tree.node_count);
}
