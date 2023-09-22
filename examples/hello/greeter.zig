const std = @import("std");
const zin = @import("../../src/App.zig");

fn myHeader(ctx: *zin.Context) !void {
    try ctx.res.headers.append("x-server-lang", "zig");
}

fn logware(ctx: *zin.Context) !void {
    std.log.debug("{any} {s}", .{ ctx.req.method, ctx.req.target });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }

    var app = try zin.App.init(.{
        .allocator = gpa.allocator(),
    });
    defer app.deinit();

    try app.use(myHeader);
    try app.use(logware);

    try app.get("/version", struct {
        fn handle(ctx: *zin.Context) !void {
            try ctx.text("0.0.1\n");
        }
    }.handle);

    try app.get("/greet/:name", struct {
        fn h(ctx: *zin.Context) !void {
            const name = ctx.params.get("name").?;
            const msg = try std.fmt.allocPrint(ctx.res.allocator, "Hello, {s}!\n", .{name});
            try ctx.text(msg);
        }
    }.h);

    try app.listen();
}
