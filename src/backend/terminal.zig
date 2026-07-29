pub const limits = @import("terminal/limits.zig");
pub const input = @import("terminal/input.zig");

pub const Event = @import("terminal/event.zig").Event;
pub const LoopAction = @import("terminal/event.zig").LoopAction;
pub const LoopOptions = @import("terminal/event.zig").LoopOptions;
pub const Surface = @import("terminal/surface.zig").Surface;
pub const TerminalCanvas = @import("terminal/canvas.zig").TerminalCanvas;
pub const TextAttributes = @import("terminal/text_style.zig").Attributes;
pub const TextStyle = @import("terminal/text_style.zig").TextStyle;
pub const ImageProtocol = @import("terminal/image.zig").Protocol;
pub const GraphicsCapabilities = @import("terminal/terminal.zig").GraphicsCapabilities;
pub const detect_image_protocol = @import("terminal/image.zig").detect;
pub const query_graphics_capabilities =
    @import("terminal/terminal.zig").query_graphics_capabilities;
pub const run_event_loop = @import("terminal/event.zig").run_event_loop;

pub const widgets = struct {
    pub const Badge = @import("terminal/widgets/badge.zig").Badge;
    pub const BadgeStyle = @import("terminal/widgets/badge.zig").BadgeStyle;
    pub const FuzzyText = @import("terminal/widgets/fuzzy_text.zig").FuzzyText;
    pub const Label = @import("terminal/widgets/label.zig").Label;
    pub const Inline = @import("terminal/widgets/inline.zig").Inline;
    pub const Image = @import("terminal/widgets/image.zig").Image;
    pub const Span = @import("terminal/widgets/inline.zig").Span;
    pub const List = @import("terminal/widgets/list.zig").List;
    pub const ListItem = @import("terminal/widgets/list.zig").Item;
    pub const ListVisual = @import("terminal/widgets/list.zig").Visual;
    pub const Panel = @import("terminal/widgets/panel.zig").Panel;
    pub const PanelChrome = @import("terminal/widgets/panel.zig").Chrome;
    pub const Scrollbar = @import("terminal/widgets/scrollbar.zig").Scrollbar;
    pub const ScrollbarStyle = @import("terminal/widgets/scrollbar.zig").ScrollbarStyle;
    pub const Segmented = @import("terminal/widgets/segmented.zig").Segmented;
    pub const SegmentItem = @import("terminal/widgets/segmented.zig").Item;
    pub const StatusHint = @import("terminal/widgets/status_line.zig").Hint;
    pub const StatusLine = @import("terminal/widgets/status_line.zig").StatusLine;
    pub const StatusVisual = @import("terminal/widgets/status_line.zig").Visual;
    pub const TextInputOptions = @import("terminal/widgets/text_input.zig").Options;
    pub const draw_text_input = @import("terminal/widgets/text_input.zig").draw;
};
