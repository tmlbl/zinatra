const std = @import("std");
const http = std.http;
const context = @import("./Context.zig");
const Context = context.Context;
const mime = @import("./mime.zig");

const Self = @This();

root: []const u8 = "/var/lib/html",

pub fn init(self: *Self, dirname: []const u8) void {
    self.root = dirname;
}

pub fn handle(self: *Self, ctx: *Context) !void {
    const parts = &[_][]const u8{ self.root, ctx.req.target };
    const abs = try std.fs.path.join(ctx.res.allocator, parts);
    // if the file doesn't exist, fall through to other handlers
    ctx.file(abs) catch |err| {
        if (err == error.FileNotFound) {
            return;
        }
    };
}
