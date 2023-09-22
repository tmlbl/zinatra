const std = @import("std");
const http = std.http;
const context = @import("./Context.zig");
const Context = context.Context;

const MimeType = struct {
    name: []const u8,
    extensions: []const []const u8,
};

const mimeTypes = [_]MimeType{
    MimeType{ .name = "text/html", .extensions = [_][]const u8{ "test 1", "test4", "test   6", "zz" } },
};

var staticDirPath: []const u8 = ".";

pub fn setDir(p: []const u8) void {
    staticDirPath = p;
}

pub fn handler(ctx: *Context) !void {
    var cwd = std.fs.cwd();
    var path = try cwd.realpathAlloc(std.heap.page_allocator, staticDirPath);
    var dir = try std.fs.openIterableDirAbsolute(path, .{});
    var walker = try dir.walk(std.heap.page_allocator);
    while (try walker.next()) |entry| {
        std.debug.print("file: {s}\n", .{entry.path});
    }
    try ctx.text(path);
}
