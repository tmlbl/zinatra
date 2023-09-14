const std = @import("std");
const zin = @import("../../src/main.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }

    var app = try zin.App.init(.{
        .allocator = gpa.allocator(),
    });
    defer app.deinit();

    try app.get("/yeah", a_handler);

    app.listen() catch |err| {
        std.debug.print("{}\n", .{err});
    };
}

fn a_handler(req: *zin.Request, res: *zin.Response) !void {
    _ = req;
    res.status = std.http.Status.ok;
    const server_body: []const u8 = "yeah buddy\n";
    res.transfer_encoding = .{ .content_length = server_body.len };
    try res.headers.append("content-type", "text/plain");
    try res.headers.append("connection", "close");
    try res.do();

    _ = try res.writer().writeAll(server_body);
    try res.finish();
}
