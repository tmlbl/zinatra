const std = @import("std");
const zin = @import("../../src/App.zig");

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
