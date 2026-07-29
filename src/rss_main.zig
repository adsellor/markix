const std = @import("std");
const terminal = @import("backend/terminal.zig");
const Application = @import("rss/application.zig").Application;
const theme = @import("app/theme.zig");
const view = @import("rss/view.zig");

const Context = struct {
    canvas: *terminal.TerminalCanvas,
    application: *Application,
};

pub fn main(init: std.process.Init) !void {
    const home = init.environ_map.get("HOME") orelse ".";
    theme.configure(init.environ_map.get("MARKIX_THEME"));
    var canvas = try terminal.TerminalCanvas.init_auto_size(init.gpa);
    defer canvas.deinit();
    try canvas.set_refresh_limit(60);
    const graphics = terminal.query_graphics_capabilities(init.io) catch
        terminal.GraphicsCapabilities{};
    canvas.set_image_protocol(terminal.detect_image_protocol(
        graphics.sixel,
        graphics.kitty,
        init.environ_map.get("MARKIX_IMAGE_PROTOCOL"),
    ));

    const application = try Application.create(init.gpa, init.io, home);
    defer application.destroy(init.gpa);
    try application.load(home);
    var context = Context{ .canvas = &canvas, .application = application };
    try terminal.run_event_loop(
        init.io,
        &canvas,
        .{},
        Context,
        &context,
        event_callback,
    );
}

fn event_callback(context: *Context, event: terminal.Event) !terminal.LoopAction {
    return switch (event) {
        .key => |key| if (try context.application.handle_key(key))
            .redraw
        else
            .stop,
        .resize => .redraw,
        .poll => if (try context.application.poll_background())
            .redraw
        else
            .wait,
        .frame => frame: {
            try view.render(context.application, context.canvas);
            break :frame .wait;
        },
    };
}
