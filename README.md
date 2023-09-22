Zinatra
=======

Zinatra is an HTTP server framework based on Zig's `std.http.Server`, with a
familiar high-level API.

```zig
const std = @import("std");
const zin = @import("zinatra");

fn greet(ctx: *zin.Context) !void {
    try ctx.text("Hello, world!");
}

pub fn main() !void {
    var app = try zin.App.init(.{
        .allocator = std.heap.page_allocator,
    });
    defer app.deinit();

    try app.get("/greet", greet);

    try app.listen();
}
```

Perhaps your next "microservice" at work could be in Zig! Think about it...

## TODO

* Customizable error handlers
* Static web server
