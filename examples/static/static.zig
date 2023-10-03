const std = @import("std");
const zin = @import("../../src/App.zig");

fn greet(ctx: *zin.Context) !void {
    try ctx.text("hello");
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var app = try zin.App.init(.{
        .allocator = allocator,
    });
    defer app.deinit();

    var buf = try allocator.alloc(u8, 1024);
    defer allocator.free(buf);
    const cwd = try std.os.getcwd(buf);

    try zin.Static.init(cwd, allocator);
    defer zin.Static.deinit();

    try app.use(zin.Static.handler);

    try app.get("/api", greet);

    try app.listen();
}
