const std = @import("std");

const mime = @import("./mime.zig");

pub const Request = std.http.Server.Request;
pub const Response = std.http.Server.Response;
pub const Handler = *const fn (*Context) anyerror!void;

pub const Error = error{
    ParseError,
};

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

    /// Access the arena allocator for the current request
    pub fn allocator(self: *Context) std.mem.Allocator {
        return self.arena.allocator();
    }

    /// Respond with a body of type text/plain
    pub fn text(self: *Context, status: std.http.Status, msg: []const u8) !void {
        try self.req.respond(msg, .{
            .status = status,
            .extra_headers = self.headers.items,
        });
    }

    /// Respond with a value serialized to JSON
    pub fn json(self: *Context, status: std.http.Status, value: anytype) !void {
        try self.headers.append(.{ .name = "Content-Type", .value = "application/json" });

        var out = std.ArrayList(u8).init(self.allocator());
        defer out.deinit();

        try std.json.stringify(value, .{}, out.writer());

        try self.req.respond(out.items, .{
            .status = status,
            .extra_headers = self.headers.items,
        });
    }

    /// Parse the request body as JSON into type T
    pub fn parseJson(self: *Context, comptime T: type) !T {
        const reader = try self.req.reader();
        const size = self.req.head.content_length.?;
        const data = try reader.readAllAlloc(self.allocator(), size);

        const parsed = std.json.parseFromSlice(
            T,
            self.allocator(),
            data,
            .{},
        ) catch {
            return Error.ParseError;
        };

        return parsed.value;
    }

    /// Send a static file as the response. The MIME type will be determined
    /// from the file extension
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

        const buf = try self.allocator().alloc(u8, 4096);
        defer self.allocator().free(buf);

        var response = self.req.respondStreaming(.{
            .send_buffer = buf,
            .content_length = stat.size,
            .respond_options = .{
                .extra_headers = self.headers.items,
            },
        });

        try response.writer().writeFile(f);
        try response.end();
    }

    pub fn fmt(self: *Context, status: std.http.Status, comptime fstr: []const u8, value: anytype) !void {
        const msg = try std.fmt.allocPrint(self.allocator(), fstr, value);
        try self.text(status, msg);
    }
};
