const std = @import("std");
const zin = @import("../../src/main.zig");

fn myHeader(ctx: *zin.Context) !void {
    try ctx.res.headers.append("x-server-lang", "zig");
}

fn terminator(ctx: *zin.Context) !void {
    try ctx.text("this request is over!");
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
    try app.use(terminator);

    try app.get("/version", struct {
        fn handle(ctx: *zin.Context) !void {
            try ctx.text("0.0.1");
        }
    }.handle);

    try app.get("/greet/:name", struct {
        fn h(ctx: *zin.Context) !void {
            const name = ctx.params.get("name").?;
            const msg = try std.fmt.allocPrint(ctx.res.allocator, "Hello, {s}!", .{name});
            try ctx.text(msg);
        }
    }.h);

    try app.get("/rest/object/:id", struct {
        fn h(ctx: *zin.Context) !void {
            try ctx.json(struct {
                id: []const u8,
            }{ .id = ctx.params.get("id").? });
        }
    }.h);

    try app.listen();
}

// const Greeting = struct {
//     time: i128,
//     msg: []const u8,
// };

// fn greet(ctx: *zin.Context) !void {
//     const name = ctx.params.get("name").?;
//     try ctx.json(Greeting{
//         .time = std.time.nanoTimestamp(),
//         .msg = try std.fmt.allocPrint(ctx.res.allocator, "Hello, {s}!", .{name}),
//     });
// }
