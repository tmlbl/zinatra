const std = @import("std");

const mime = @import("./mime.zig");

pub const Request = std.http.Server.Request;
pub const Response = std.http.Server.Response;
pub const Handler = *const fn (*Context) anyerror!void;

pub const Context = struct {
    arena: std.heap.ArenaAllocator,
    req: *Request,
    params: std.StringHashMap([]const u8),
    headers: std.ArrayList(std.http.Header),

    pub fn deinit(self: *Context) void {
        self.params.deinit();
        self.headers.deinit();
        self.arena.deinit();
    }

    pub fn allocator(self: *Context) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn json(self: *Context, value: anytype) !void {
        try self.headers.append(.{ .name = "Content-Type", .value = "application/json" });

        var out = std.ArrayList(u8).init(self.allocator());
        defer out.deinit();

        try std.json.stringify(value, .{}, out.writer());

        try self.req.respond(out.items, .{
            .extra_headers = self.headers.items,
        });
    }

    pub fn text(self: *Context, msg: []const u8) !void {
        try self.statusText(std.http.Status.ok, msg);
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

        // get file suffix and set content-type
        const suffix = std.fs.path.extension(path);
        const mt = mime.getMimeMap().get(suffix);
        if (mt != null) {
            try self.headers.append(.{ .name = "Content-Type", .value = mt.? });
        }

        const buf = try self.allocator().alloc(u8, std.mem.page_size);
        defer self.allocator().free(buf);

        var response = self.req.respondStreaming(.{
            .send_buffer = buf,
            .content_length = stat.size,
            .respond_options = .{
                .extra_headers = self.headers.items,
            },
        });

        try response.writer().writeFile(f);
    }

    pub fn statusText(self: *Context, status: std.http.Status, msg: []const u8) !void {
        try self.req.respond(msg, .{
            .status = status,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/plain" },
            },
        });
    }
};
