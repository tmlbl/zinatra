const std = @import("std");
const zin = @import("../../src/main.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }

    var app = try zin.App.init(gpa.allocator());
    defer app.deinit();

    const addr = try std.net.Address.parseIp4("127.0.0.1", 3737);

    std.log.debug("listening on {}...", .{addr});
    try app.listen(addr);
}
