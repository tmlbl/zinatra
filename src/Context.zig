const Context = @This();

arena: *std.heap.ArenaAllocator,
req: *std.http.Server.Request,
params: std.StringHashMap([]const u8),
headers: std.ArrayList(std.http.Header),
requestHeaders: std.StringHashMap([]const u8),

pub fn init(
    arena: *std.heap.ArenaAllocator,
    req: *std.http.Server.Request,
    params: std.StringHashMap([]const u8),
) !Context {
    return Context{
        .arena = arena,
        .req = req,
        .params = params,
        .headers = try std.ArrayList(std.http.Header).initCapacity(arena.allocator(), 64),
        .requestHeaders = std.StringHashMap([]const u8).init(arena.allocator()),
    };
}

pub fn deinit(self: *Context) void {
    self.params.deinit();
    self.requestHeaders.deinit();
    self.arena.deinit();
}

/// Access the arena allocator for the current request
pub fn allocator(self: *Context) std.mem.Allocator {
    return self.arena.allocator();
}

/// Add a header to the response
pub fn addHeader(self: *Context, header: std.http.Header) !void {
    try self.headers.append(self.allocator(), header);
}

/// Retrieve the value of a request header
pub fn getHeader(self: *Context, name: []const u8) ![]const u8 {
    if (self.requestHeaders.count() == 0) {
        var it = self.req.iterateHeaders();
        while (it.next()) |header| {
            try self.requestHeaders.put(
                try std.ascii.allocLowerString(self.allocator(), header.name),
                try self.allocator().dupe(u8, header.value),
            );
        }
    }

    const lowerName = try std.ascii.allocLowerString(self.allocator(), name);
    const value = self.requestHeaders.get(lowerName);
    if (value != null) {
        return value.?;
    } else {
        return "";
    }
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
    try self.headers.append(self.allocator(), .{
        .name = "Content-Type",
        .value = "application/json",
    });

    const out = try std.json.Stringify.valueAlloc(self.allocator(), value, .{});

    try self.req.respond(out, .{
        .status = status,
        .extra_headers = self.headers.items,
    });
}

/// Parse the request body as JSON into type T
pub fn parseJson(self: *Context, comptime T: type) !T {
    var buf: [1024]u8 = undefined;
    const reader = try self.req.readerExpectContinue(&buf);
    var jsonReader = std.json.Reader.init(
        self.allocator(),
        reader,
    );

    const parsed = std.json.parseFromTokenSource(
        T,
        self.allocator(),
        &jsonReader,
        .{},
    ) catch {
        return error.ParseError;
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
        try self.addHeader(.{ .name = "Content-Type", .value = mt.? });
    }

    const buf = try self.allocator().alloc(u8, 4096);
    defer self.allocator().free(buf);

    var response = try self.req.respondStreaming(buf, .{
        .content_length = stat.size,
        .respond_options = .{
            .extra_headers = self.headers.items,
        },
    });

    var readBuf: [1024]u8 = undefined;

    while (true) {
        const read = try f.read(&readBuf);
        if (read == 0) {
            break;
        }
        _ = try response.writer.writeAll(readBuf[0..read]);
    }
    try response.writer.flush();
    try response.end();
}

pub fn fmt(self: *Context, status: std.http.Status, comptime fstr: []const u8, value: anytype) !void {
    const msg = try std.fmt.allocPrint(self.allocator(), fstr, value);
    try self.text(status, msg);
}

const std = @import("std");
const mime = @import("./mime.zig");

pub const Error = error{
    ParseError,
};
