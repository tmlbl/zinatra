const std = @import("std");

const router = @import("./route_tree.zig");

pub const Request = std.http.Server.Request;
pub const Response = std.http.Server.Response;

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
};

pub const Handler = *const fn (*Context) anyerror!void;

const max_header_size = 256;

var handle_requests = true;
var server: ?std.http.Server = null;

pub const Options = struct {
    allocator: std.mem.Allocator,
    host: []const u8 = "127.0.0.1",
    port: u16 = 3737,
};

pub const App = struct {
    allocator: std.mem.Allocator,
    router: *router.RouteTree(Handler),
    server: std.http.Server,
    addr: std.net.Address,

    pub fn init(opts: Options) !*App {
        var app = try opts.allocator.create(App);

        app.allocator = opts.allocator;
        app.addr = try std.net.Address.parseIp4(opts.host, opts.port);

        app.router = try router.RouteTree(Handler).init(opts.allocator, "/", null);
        app.server = std.http.Server.init(opts.allocator, .{
            .reuse_address = true,
            .reuse_port = true,
        });
        server = app.server;
        return app;
    }

    pub fn deinit(self: *App) void {
        self.server.deinit();
        self.router.deinit();
        self.allocator.destroy(self);
    }

    pub fn get(app: *App, path: []const u8, handler: Handler) !void {
        try app.router.add(path, handler);
    }

    pub fn listen(self: *App) !void {
        try std.os.sigaction(std.os.SIG.INT, &.{
            .handler = .{ .handler = &App.onSigint },
            .mask = std.os.empty_sigset,
            .flags = (std.os.SA.SIGINFO | std.os.SA.RESTART),
        }, null);

        try self.server.listen(self.addr);
        std.log.debug("listening on {}...", .{self.addr});
        try self.runServer();
    }

    fn onSigint(_: c_int) callconv(.C) void {
        std.os.exit(0);
    }

    fn runServer(self: *App) !void {
        outer: while (handle_requests) {
            var res = self.server.accept(.{
                .allocator = self.allocator,
                .header_strategy = .{ .dynamic = max_header_size },
            }) catch |err| {
                if (err == error.SocketNotListening and handle_requests == false) {
                    std.debug.print("socket not listening\n", .{});
                    break;
                }
                return err;
            };
            defer res.deinit();

            while (res.reset() != .closing) {
                res.wait() catch |err| switch (err) {
                    error.HttpHeadersInvalid => continue :outer,
                    error.EndOfStream => continue,
                    else => return err,
                };

                self.handleRequest(&res) catch |err| {
                    std.log.err("{} {s} {}", .{ res.status, res.request.target, err });
                };
            }
        }
    }

    fn handleRequest(app: *App, res: *std.http.Server.Response) !void {
        var params = std.StringHashMap([]const u8).init(app.allocator);
        defer params.deinit();
        const handler = app.router.resolve(res.request.target, &params);
        if (handler != null) {
            var ctx = Context{
                .req = &res.request,
                .res = res,
                .params = params,
            };
            try handler.?(&ctx);
        } else {
            res.status = std.http.Status.not_found;
            const server_body: []const u8 = "not found\n";
            res.transfer_encoding = .{ .content_length = server_body.len };
            try res.headers.append("content-type", "text/plain");
            try res.headers.append("connection", "close");
            try res.do();

            _ = try res.writer().writeAll(server_body);
            try res.finish();
        }
    }
};

test "create an app" {
    var app = try App.init(std.testing.allocator);
    defer app.deinit();
}
