const std = @import("std");
const zin = @import("../../src/App.zig");

// zin.Handler functions accept a *Context and return !void
fn greet(ctx: *zin.Context) !void {
    // params can be accessed via the built-in map
    const name = ctx.params.get("name").?;
    // each context creates an arena allocator, so you can make quick
    // per-request allocations without calling free
    const msg = try std.fmt.allocPrint(ctx.allocator(), "Hello, {s}!", .{name});
    // Context helper methods for common response types
    try ctx.text(msg);
}

// middleware functions are also of the type zin.Handler, they just don't call
// ctx.res.finish()
fn defaultHeaders(ctx: *zin.Context) !void {
    try ctx.res.headers.append("server", "zin/v0.1.0");
}

// middleware functions can access properties of the response after handlers run
// when added with App.after
fn logger(ctx: *zin.Context) !void {
    const time = std.time.milliTimestamp();
    const method = @tagName(ctx.req.method);
    const status = @tagName(ctx.res.status);
    std.log.debug("{d} {s} {s} {s}", .{ time, method, ctx.req.target, status });
}

pub fn main() !void {
    var app = try zin.App.init(.{
        .allocator = std.heap.page_allocator,
    });
    defer app.deinit();

    try app.use(zin.mw.queryStringParser);

    try app.use(defaultHeaders);

    try app.get("/greet/:name", greet);

    try app.after(logger);

    try app.listen();
}
