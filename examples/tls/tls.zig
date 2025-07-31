const std = @import("std");
const zin = @import("zinatra");

fn hello(ctx: *zin.Context) !void {
    std.log.info("received a request", .{});
    try ctx.text(.ok, "hey there");
}

pub fn main() !void {
    var app = try zin.new(.{
        .port = 3125,
    });
    defer app.deinit();

    try app.get("/hello", hello);

    try app.listenTls("cert.pem", "key.pem");
}
