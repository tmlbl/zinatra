const std = @import("std");
const http = std.http;
const Context = @import("./Context.zig");
const mime = @import("./mime.zig");

const Self = @This();

root: []const u8 = "/var/lib/html",

pub fn init(self: *Self, dirname: []const u8) void {
    self.root = dirname;
}

pub fn handle(self: *Self, ctx: *Context) !void {
    var target = ctx.req.head.target;
    if (std.mem.eql(u8, target, "/")) {
        target = "index.html";
    }
    const parts = &[_][]const u8{ self.root, target };
    const abs = try std.fs.path.join(ctx.allocator(), parts);

    // if the file doesn't exist, fall through to other handlers
    ctx.file(abs) catch |err| {
        if (err == error.FileNotFound) {
            return;
        } else {
            return err;
        }
    };
}
