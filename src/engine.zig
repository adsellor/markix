const box_mod = @import("engine/box.zig");
const rect_mod = @import("engine/rect.zig");
const tree_mod = @import("engine/tree.zig");
const layout_mod = @import("engine/layout.zig");
const style_mod = @import("engine/style.zig");
const dom_mod = @import("engine/dom.zig");
const measure_mod = @import("engine/measure.zig");

pub const Rect = rect_mod.Rect;
pub const Edges = rect_mod.Edges;

pub const Sizing = box_mod.Sizing;
pub const Direction = box_mod.Direction;
pub const Alignment = box_mod.Alignment;
pub const AlignX = box_mod.AlignX;
pub const AlignY = box_mod.AlignY;
pub const Layout = box_mod.Layout;

pub const Color = style_mod.Color;
pub const Style = style_mod.Style;

pub const Element = dom_mod.Element;

pub const Tree = tree_mod.Tree;
pub const Node = tree_mod.Node;
pub const Index = tree_mod.Index;
pub const none = tree_mod.none;

pub const Size = layout_mod.Size;
pub const Measure = layout_mod.Measure;
pub const TextIterator = layout_mod.TextIterator;
pub const Options = layout_mod.Options;
pub const unbounded = layout_mod.unbounded;
pub const resolve = layout_mod.resolve;

pub const measure = measure_mod;

pub const dsl = @import("engine/dsl.zig");

pub const html = @import("engine/html.zig");

test {
    _ = @import("engine/tests.zig");
    _ = tree_mod;
    _ = box_mod;
    _ = rect_mod;
    _ = style_mod;
    _ = dom_mod;
    _ = measure_mod;
}
