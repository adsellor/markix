const std = @import("std");
const LayoutInfo = @import("Layout.zig").LayoutInfo;
const Allocator = std.mem.Allocator;

pub fn TreeNode(comptime T: type) type {
    return struct {
        const Self = @This();
        element: T,
        layout_info: LayoutInfo,
        is_dirty: bool,
        children: []const *const Self,
        ref_count: std.atomic.Value(u32),
        allocator: Allocator,

        pub fn init(
            allocator: Allocator,
            element: T,
            layout_info: LayoutInfo,
            is_dirty: bool,
            children: []const *const Self,
        ) !*Self {
            const node = try allocator.create(Self);
            node.* = Self{
                .element = element,
                .layout_info = layout_info,
                .is_dirty = is_dirty,
                .children = children,
                .ref_count = std.atomic.Value(u32).init(1),
                .allocator = allocator,
            };

            for (children) |child| {
                const mutable_child = @constCast(child);
                _ = mutable_child.ref_count.fetchAdd(1, .monotonic);
            }

            return node;
        }

        pub fn deinit(self: *const Self) void {
            const mutable_self = @constCast(self);
            const count = mutable_self.ref_count.fetchSub(1, .monotonic);

            if (count == 1) {
                for (self.children) |child| {
                    child.deinit();
                }
                self.allocator.free(self.children);
                self.allocator.destroy(mutable_self);
            }
        }

        pub fn retain(self: *const Self) *const Self {
            const mutable_self = @constCast(self);
            _ = mutable_self.ref_count.fetchAdd(1, .monotonic);
            return self;
        }
    };
}
