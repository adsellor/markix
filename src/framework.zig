pub const limits = @import("framework/limits.zig");
pub const flex = @import("framework/layout/flex.zig");
pub const fuzzy = @import("framework/fuzzy.zig");
pub const grid = @import("framework/layout/grid.zig");
pub const input = @import("framework/input.zig");

pub const Color = @import("framework/layout/color.zig").Color;
pub const Rect = @import("framework/layout/rect.zig").Rect;
pub const Style = @import("framework/style.zig").Style;
pub const TextSelectionStyle = @import("framework/style.zig").TextSelectionStyle;
pub const layout_tree = @import("framework/layout/tree.zig");
pub const LayoutElement = layout_tree.LayoutElement;
pub const LayoutTree = layout_tree.LayoutTree;
pub const Tree = layout_tree.Tree;

pub const widgets = struct {
    pub const TextInput = @import("framework/widgets/text_input.zig").TextInput;
    pub const TextInputAction = @import("framework/widgets/text_input.zig").Action;
};
