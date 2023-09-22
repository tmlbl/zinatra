const std = @import("std");

pub const Request = std.http.Server.Request;
pub const Response = std.http.Server.Response;
pub const Handler = *const fn (*Context) anyerror!void;

pub const Context = struct {
    req: *Request,
    res: *Response,
    params: std.StringHashMap([]const u8),

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
        try self.res.do();

        self.res.transfer_encoding = .{ .content_length = msg.len };
        try self.res.writer().writeAll(msg);
        try self.res.finish();
    }
};
