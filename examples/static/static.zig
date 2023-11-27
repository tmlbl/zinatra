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

    const buf = try allocator.alloc(u8, 1024);
    defer allocator.free(buf);
    const cwd = try std.os.getcwd(buf);

    std.log.debug("serving files from {s}...", .{cwd});
    static.init(cwd);

    try app.use(handleStatic);

    try app.listen();
}
