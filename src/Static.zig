const std = @import("std");
const http = std.http;
const context = @import("./Context.zig");
const Context = context.Context;

const MimeType = struct {
    name: []const u8,
    extensions: []const []const u8,
};

const mimeTypes = [_]MimeType{
    MimeType{ .name = "text/html", .extensions = &[_][]const u8{ "html", "htm" } },
    MimeType{ .name = "text/javascript", .extensions = &[_][]const u8{"js"} },
    MimeType{ .name = "text/css", .extensions = &[_][]const u8{"css"} },
    MimeType{ .name = "image/gif", .extensions = &[_][]const u8{"gif"} },
    MimeType{ .name = "image/jpeg", .extensions = &[_][]const u8{ "jpeg", "jpg" } },
    MimeType{ .name = "image/vnd.microsoft.icon", .extensions = &[_][]const u8{"ico"} },
};

var mimeExtMap: ?std.StringHashMap([]const u8) = null;

var staticRoot: ?std.fs.Dir = null;

pub fn init(dirname: []const u8, allocator: std.mem.Allocator) !void {
    staticRoot = try std.fs.openDirAbsolute(dirname, .{});
    mimeExtMap = std.StringHashMap([]const u8).init(allocator);
    for (mimeTypes) |mt| {
        for (mt.extensions) |ext| {
            try mimeExtMap.?.put(ext, mt.name);
        }
    }
}

pub fn deinit() void {
    mimeExtMap.?.deinit();
}

pub fn handler(ctx: *Context) !void {
    var target = ctx.req.target;
    if (std.mem.eql(u8, target, "/")) {
        target = "/index.html";
    }
    // TODO: more intelligent about what is and isn't a file target
    var file = staticRoot.?.openFile(target[1..], .{}) catch |err| {
        if (err == error.FileNotFound) {
            return;
        }
        return;
    };
    const dot = std.mem.lastIndexOf(u8, target, ".").?;
    var suffix = target[dot + 1 ..];
    const mt = mimeExtMap.?.get(suffix);
    if (mt != null) {
        try ctx.res.headers.append("Content-Type", mt.?);
    }
    var stat = try file.stat();
    var size = try std.fmt.allocPrint(ctx.res.allocator, "{d}", .{stat.size});
    defer ctx.res.allocator.free(size);
    try ctx.res.headers.append("Content-Length", size);
    try ctx.res.do();

    var buf = try ctx.res.allocator.alloc(u8, 4096);
    defer ctx.res.allocator.free(buf);
    while (true) {
        const n_read = try file.read(buf);
        if (n_read == 0) {
            break;
        }
        _ = try ctx.res.writer().write(buf[0..n_read]);
    }
    try ctx.res.finish();
}
