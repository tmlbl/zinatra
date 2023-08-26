const std = @import("std");

const router = @import("./route_tree.zig");
const types = @import("./types.zig");

pub const Handler = types.Handler;
pub const Request = std.http.Server.Request;
pub const Response = std.http.Server.Response;

const max_header_size = 256;

var handle_requests = true;

pub const App = struct {
    allocator: std.mem.Allocator,
    router: *router.RouteTree(Handler),
    server: std.http.Server,

    pub fn init(a: std.mem.Allocator) !*App {
        var app = try a.create(App);
        app.allocator = a;
        app.router = try router.RouteTree(Handler).init(a, "/", null);
        app.server = std.http.Server.init(a, .{
            .reuse_address = true,
            .reuse_port = true,
        });
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

    pub fn listen(self: *App, addr: std.net.Address) !void {
        try std.os.sigaction(std.os.SIG.INT, &.{
            .handler = .{ .handler = &App.onSigint },
            .mask = std.os.empty_sigset,
            .flags = (std.os.SA.SIGINFO | std.os.SA.RESTART),
        }, null);

        try self.server.listen(addr);
        try self.runServer();
    }

    fn onSigint(_: c_int) callconv(.C) void {
        std.debug.print("thank you for interrupting...\n", .{});
        handle_requests = false;
    }

    fn runServer(self: *App) !void {
        outer: while (handle_requests) {
            var res = self.server.accept(.{
                .allocator = self.allocator,
                .header_strategy = .{ .dynamic = max_header_size },
            }) catch |err| {
                if (err == error.SocketNotListening and handle_requests == false) {
                    break;
                }
                return err;
            };
            errdefer res.deinit();

            while (res.reset() != .closing) {
                res.wait() catch |err| switch (err) {
                    error.HttpHeadersInvalid => continue :outer,
                    error.EndOfStream => continue,
                    else => return err,
                };

                self.handleRequest(&res) catch |err| {
                    std.debug.print("{} oops...\n", .{err});
                };
            }
        }
    }

    fn handleRequest(app: *App, res: *std.http.Server.Response) !void {
        var params = std.StringHashMap([]const u8).init(app.allocator);
        defer params.deinit();
        const handler = app.router.resolve(res.request.target, &params);
        if (handler != null) {
            try handler.?(&res.request, res);
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

pub fn new(a: std.mem.Allocator) !App {
    return App{
        .allocator = a,
        .router = try router.RouteTable.init(a),
    };
}

test "create an app" {
    var app = try App.init(std.testing.allocator);
    defer app.deinit();
}
