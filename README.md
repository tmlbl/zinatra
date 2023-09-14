Zinatra
=======

Zinatra is an HTTP server framework for Zig, with a familiar API. Build your
server by creating an `App` object, registering `Handler` functions, and calling
`App.listen`:

```zig
var app = try zin.App.init(.{
    .allocator = testing.allocator,
});
defer app.deinit();

try app.get("/version", struct {
    fn handle(ctx: *zin.Context) !void {
        try ctx.text("0.0.1");
    }
}.handle);

try app.listen();
```

Route parameters can be declared on registration, and are then available in the
`Context` object:

```zig
try app.get("/greet/:name", struct {
    fn h(ctx: *zin.Context) !void {
        const name = ctx.params.get("name").?;
        const msg = try std.fmt.allocPrint(ctx.res.allocator, "Hello, {s}!", .{name});
        try ctx.text(msg);
    }
}.h);
```

Oh you need JSON? The `Context` object encapsulates the request and response
types from `std.http` so you can really do whatever you need. A framework should
make it super easy, though.

```zig
try app.get("/rest/object/:id", struct {
    fn h(ctx: *zin.Context) !void {
        try ctx.json(struct {
            id: []const u8,
        }{ .id = ctx.params.get("id").? });
    }
}.h);
```

Perhaps your next "microservice" at work could be in Zig! Think about it...

## TODO

* Multithreading
* More router tests
* Middleware
