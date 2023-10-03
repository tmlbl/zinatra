const std = @import("std");
const zin = @import("../../src/App.zig");

var static = zin.Static{};

fn handleStatic(ctx: *zin.Context) !void {
    return static.handle(ctx);
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
    static.init(cwd);

    try app.use(handleStatic);

    try app.listen();
}
