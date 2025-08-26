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
    try ctx.text(.ok, msg);
}

// zin.Context provides shortcuts for common cases, like sending JSON
fn sendJson(ctx: *zin.Context) !void {
    try ctx.json(.ok, .{
        .foo = "bar",
    });
}

const Person = struct {
    name: []const u8,
    age: usize,
};

fn receiveJson(ctx: *zin.Context) !void {
    const person = try ctx.parseJson(Person);
    std.log.debug("name: {s} age: {d}", .{ person.name, person.age });
    try ctx.json(.ok, person);
}

// Middleware functions have the same function signature as route handlers
fn defaultHeaders(ctx: *zin.Context) !void {
    try ctx.addHeader(.{ .name = "server", .value = "zin/v0.1.0" });
}

fn auth(ctx: *zin.Context) !void {
    const authorization = try ctx.getHeader("Authorization");
    if (authorization.len == 0) {
        try ctx.text(.unauthorized, "missing authorization header");
    }
}

pub fn main() !void {
    var app = try zin.new(.{});
    defer app.deinit();

    // optionally add query string parameters to route parameters map
    try app.use(zin.mw.queryStringParser);

    try app.use(defaultHeaders);
    try app.use(auth);

    // use classic route templating syntax to register handlers
    try app.get("/greet/:name", greet);

    try app.get("/json", sendJson);
    try app.post("/json", receiveJson);

    try app.listen();
}
