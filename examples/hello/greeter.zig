const std = @import("std");
const zin = @import("../../src/App.zig");

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
