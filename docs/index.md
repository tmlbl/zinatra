zinatra
=======

Zinatra is a wonderfully easy-to-use web application framework in native Zig,
based on `std.http.Server`. It provides an ergonomic, minimal API that allows
for advanced functionality from only a few lines of code.

# Getting Started

Zinatra's API centers around the `Context` type. An instance of `Context` is
created for incoming request, and the request and response can be fully
managed by interacting with it inside a `Handler` function.

```zig
const zin = @import("zinatra");

fn greet(ctx: *zin.Context) !void {
  try ctx.text(.ok, "hello!");
}
```


