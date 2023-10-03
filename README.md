Zinatra
=======

Zinatra is an HTTP server framework based on Zig's `std.http.Server`, with a
familiar high-level API.

```zig
const std = @import("std");
const zin = @import("zinatra");

fn greet(ctx: *zin.Context) !void {
    const name = ctx.params.get("name").?;
    const msg = try std.fmt.allocPrint(ctx.allocator, "Hello, {s}!", .{name});
    try ctx.text(msg);
}

pub fn main() !void {
    var app = try zin.App.init(.{
        .allocator = std.heap.page_allocator,
    });
    defer app.deinit();

    try app.get("/greet/:name", greet);

    try app.listen();
}
```

Check out the examples folder for more functionality. Demos can be built quickly
from the project root like so:

```
zig build-exe examples/static/static.zig --main-pkg-path (pwd)
```

Perhaps your next "microservice" at work could be in Zig! Think about it...

## TODO

* Customizable error handlers
* Static web server
