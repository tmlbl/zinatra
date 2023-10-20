const std = @import("std");

const mime = @import("./mime.zig");

pub const Request = std.http.Server.Request;
pub const Response = std.http.Server.Response;
pub const Handler = *const fn (*Context) anyerror!void;

pub const Context = struct {
    arena: std.heap.ArenaAllocator,
    req: *Request,
    res: *Response,
    params: std.StringHashMap([]const u8),

    pub fn deinit(self: *Context) void {
        self.res.deinit();
        self.params.deinit();
        self.arena.deinit();
    }

    pub fn allocator(self: *Context) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn json(self: *Context, value: anytype) !void {
        try self.res.headers.append("Content-Type", "application/json");
        try self.res.do();

        var out = std.ArrayList(u8).init(self.res.allocator);
        defer out.deinit();

        try std.json.stringify(value, .{}, out.writer());

        self.res.transfer_encoding = .{ .content_length = out.items.len };
        try self.res.writer().writeAll(out.items);
        try self.res.finish();
    }

    pub fn text(self: *Context, msg: []const u8) !void {
        try self.res.headers.append("Content-Type", "text/plain");
        self.res.transfer_encoding = .{ .content_length = msg.len };

        try self.res.do();
        try self.res.writer().writeAll(msg);
        try self.res.finish();
    }

    pub fn file(self: *Context, path: []const u8) !void {
        var f = try std.fs.openFileAbsolute(path, .{});
        defer f.close();

        // get file size
        const stat = try f.stat();
        // if it's not a regular file, just return FileNotFound
        if (stat.kind != .file) {
            return error.FileNotFound;
        }
        self.res.transfer_encoding = .{ .content_length = stat.size };

        // get file suffix and set content-type
        const suffix = std.fs.path.extension(path);
        const mt = mime.getMimeMap().get(suffix);
        if (mt != null) {
            try self.res.headers.append("Content-Type", mt.?);
        }

        // allocate a transfer buffer
        // TODO: this should probably be from a buffer pool, or use one of the
        // built-in buffered writer types
        var buf = try self.res.allocator.alloc(u8, 512);
        defer self.res.allocator.free(buf);

        // send the respone
        try self.res.do();
        while (true) {
            const n_read = try f.read(buf);
            if (n_read == 0) {
                break;
            }
            _ = try self.res.writer().write(buf[0..n_read]);
        }
        try self.res.finish();
    }

    pub fn err(self: *Context, status: std.http.Status, msg: []const u8) !void {
        try self.res.headers.append("Content-Type", "text/plain");
        self.res.transfer_encoding = .{ .content_length = msg.len };
        self.res.status = status;

        try self.res.do();
        try self.res.writer().writeAll(msg);
        try self.res.finish();
    }
};
