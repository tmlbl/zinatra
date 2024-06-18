const std = @import("std");
const zin = @import("zinatra");

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

// zin.Context provides shortcuts for common cases, like sending JSON
fn sendJson(ctx: *zin.Context) !void {
    try ctx.json(.{
        .foo = "bar",
    });
}

// Middleware functions have the same function signature as route handlers
fn defaultHeaders(ctx: *zin.Context) !void {
    try ctx.headers.append(.{ .name = "server", .value = "zin/v0.1.0" });
}

pub fn main() !void {
    var app = try zin.App.init(.{
        .allocator = std.heap.page_allocator,
    });
    defer app.deinit();

    // optionally add query string parameters to route parameters map
    try app.use(zin.mw.queryStringParser);

    try app.use(defaultHeaders);

    // use classic route templating syntax to register handlers
    try app.get("/greet/:name", greet);

    try app.get("/json", sendJson);

    try app.listen();
}
