const std = @import("std");
const Allocator = std.mem.Allocator;

const TreeNode = @import("TreeNode.zig").TreeNode;
const LayoutInfo = @import("Layout.zig").LayoutInfo;

pub fn Tree(comptime T: type) type {
    return struct {
        const Self = @This();
        const Node = TreeNode(T);

        root: ?*const Node,
        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .root = null,
                .allocator = allocator,
            };
        }

        pub fn initWithRoot(allocator: Allocator, element: T, layout_info: LayoutInfo) !Self {
            const empty_children = try allocator.alloc(*const Node, 0);
            const root = try Node.init(allocator, element, layout_info, false, empty_children);
            return Self{
                .root = root,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.root) |root| {
                root.deinit();
            }
        }

        pub fn updateRootLayoutInfo(self: *const Self, layout_info: LayoutInfo) !Self {
            if (self.root) |root| {
                const new_children = try self.allocator.dupe(*const Node, root.children);
                const new_root = try Node.init(
                    self.allocator,
                    root.element,
                    layout_info,
                    true,
                    new_children,
                );
                return Self{
                    .root = new_root,
                    .allocator = self.allocator,
                };
            }
            return self.*;
        }

        pub fn addChildToRoot(self: *const Self, child_element: T, child_layout_info: LayoutInfo) !Self {
            if (self.root) |root| {
                const empty_children = try self.allocator.alloc(*const Node, 0);
                const new_child = try Node.init(
                    self.allocator,
                    child_element,
                    child_layout_info,
                    false,
                    empty_children,
                );

                const new_children = try self.allocator.alloc(*const Node, root.children.len + 1);
                @memcpy(new_children[0..root.children.len], root.children);
                new_children[root.children.len] = new_child;

                const new_root = try Node.init(
                    self.allocator,
                    root.element,
                    root.layout_info,
                    true,
                    new_children,
                );

                return Self{
                    .root = new_root,
                    .allocator = self.allocator,
                };
            }
            return self.*;
        }

        pub fn updateRootElement(self: *const Self, element: T) !Self {
            if (self.root) |root| {
                const new_children = try self.allocator.dupe(*const Node, root.children);
                const new_root = try Node.init(self.allocator, element, root.layout_info, root.is_dirty, new_children);
                return Self{
                    .root = new_root,
                    .allocator = self.allocator,
                };
            }
            return self.*;
        }

        pub const Path = std.ArrayList(usize);

        pub fn updateElementAtPath(self: *const Self, path: Path, element: T) !Self {
            if (self.root == null or path.items.len == 0) {
                return self.updateRootElement(element);
            }

            const new_root = try self.updateNodeAtPath(self.root.?, path.items, 0, .{ .element = element });
            return Self{
                .root = new_root,
                .allocator = self.allocator,
            };
        }

        pub fn updateLayoutInfoAtPath(self: *const Self, path: Path, layout_info: LayoutInfo) !Self {
            if (self.root == null or path.items.len == 0) {
                return self.updateRootLayoutInfo(layout_info);
            }

            const new_root = try self.updateNodeAtPath(self.root.?, path.items, 0, .{ .layout_info = layout_info });
            return Self{
                .root = new_root,
                .allocator = self.allocator,
            };
        }

        const UpdateOperation = union(enum) {
            element: T,
            layout_info: LayoutInfo,
        };

        fn updateNodeAtPath(
            self: *const Self,
            node: *const Node,
            path: []const usize,
            depth: usize,
            operation: UpdateOperation,
        ) !*const Node {
            if (depth == path.len) {
                const new_children = try self.allocator.dupe(*const Node, node.children);
                return switch (operation) {
                    .element => |elem| Node.init(self.allocator, elem, node.layout_info, true, new_children),
                    .layout_info => |layout| Node.init(self.allocator, node.element, layout, true, new_children),
                };
            }

            const child_index = path[depth];
            if (child_index >= node.children.len) {
                return error.PathOutOfBounds;
            }

            const new_child = try self.updateNodeAtPath(node.children[child_index], path, depth + 1, operation);

            const new_children = try self.allocator.alloc(*const Node, node.children.len);
            for (node.children, 0..) |child, i| {
                if (i == child_index) {
                    new_children[i] = new_child;
                } else {
                    new_children[i] = child.retain();
                }
            }

            return Node.init(self.allocator, node.element, node.layout_info, true, new_children);
        }

        pub fn getElement(self: *const Self) ?T {
            if (self.root) |root| {
                return root.element;
            }
            return null;
        }

        pub fn getLayoutInfo(self: *const Self) ?LayoutInfo {
            if (self.root) |root| {
                return root.layout_info;
            }
            return null;
        }

        pub fn isDirty(self: *const Self) bool {
            if (self.root) |root| {
                return root.is_dirty;
            }
            return false;
        }

        pub fn getChildCount(self: *const Self) usize {
            if (self.root) |root| {
                return root.children.len;
            }
            return 0;
        }

        pub fn getChildAtIndex(self: *const Self, index: usize) ?Self {
            if (self.root) |root| {
                if (index < root.children.len) {
                    return Self{
                        .root = root.children[index].retain(),
                        .allocator = self.allocator,
                    };
                }
            }
            return null;
        }

        pub fn equals(self: *const Self, other: *const Self) bool {
            return self.nodeEquals(self.root, other.root);
        }

        fn nodeEquals(self: *const Self, node1: ?*const Node, node2: ?*const Node) bool {
            if (node1 == null and node2 == null) return true;
            if (node1 == null or node2 == null) return false;

            const n1 = node1.?;
            const n2 = node2.?;

            if (!std.meta.eql(n1.element, n2.element) or
                !std.meta.eql(n1.layout_info, n2.layout_info) or
                n1.is_dirty != n2.is_dirty or
                n1.children.len != n2.children.len)
            {
                return false;
            }

            for (n1.children, n2.children) |child1, child2| {
                if (!self.nodeEquals(child1, child2)) {
                    return false;
                }
            }

            return true;
        }
    };
}
