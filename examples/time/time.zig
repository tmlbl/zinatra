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

const Message = struct {
    code: u16,
    desc: []const u8,
};

fn a_handler(ctx: *zin.Context) !void {
    try ctx.json(Message{
        .code = 37,
        .desc = "Some kinda message",
    });
}
