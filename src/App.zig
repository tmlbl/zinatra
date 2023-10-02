const std = @import("std");

const router = @import("./RouteTree.zig");
const context = @import("./Context.zig");

pub const Context = context.Context;
pub const Handler = context.Handler;
pub const Static = @import("./Static.zig");

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
    middleware: std.ArrayList(Handler),

    // per-method route trees
    get_router: *router.RouteTree(Handler),
    post_router: *router.RouteTree(Handler),

    server: std.http.Server,
    addr: std.net.Address,
    pool: *std.Thread.Pool,

    pub fn init(opts: Options) !*App {
        var app = try opts.allocator.create(App);

        app.pool = try opts.allocator.create(std.Thread.Pool);
        try app.pool.init(.{
            .allocator = opts.allocator,
            .n_jobs = 16,
        });

        app.allocator = opts.allocator;
        app.middleware = std.ArrayList(Handler).init(app.allocator);
        app.addr = try std.net.Address.parseIp4(opts.host, opts.port);

        app.get_router = try router.RouteTree(Handler).init(opts.allocator, "/", null);
        app.post_router = try router.RouteTree(Handler).init(opts.allocator, "/", null);

        app.server = std.http.Server.init(opts.allocator, .{
            .reuse_address = true,
            .reuse_port = true,
        });
        server = app.server;
        return app;
    }

    pub fn deinit(self: *App) void {
        self.server.deinit();
        self.get_router.deinit();
        self.post_router.deinit();
        self.pool.deinit();
        self.allocator.destroy(self.pool);
        self.allocator.destroy(self);
    }

    // Use adds a Handler function to the app as middleware, so it will run on
    // every request
    pub fn use(app: *App, handler: Handler) !void {
        try app.middleware.append(handler);
    }

    pub fn get(app: *App, path: []const u8, handler: Handler) !void {
        try app.get_router.add(path, handler);
    }

    pub fn post(app: *App, path: []const u8, handler: Handler) !void {
        try app.post_router.add(path, handler);
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

            res.wait() catch |err| switch (err) {
                error.HttpHeadersInvalid => continue :outer,
                error.EndOfStream => continue,
                else => return err,
            };

            try self.pool.spawn(handleRequest, .{ self, &res });
        }
    }

    fn handleRequest(app: *App, res: *std.http.Server.Response) void {
        var params = std.StringHashMap([]const u8).init(app.allocator);

        const handler = switch (res.request.method) {
            std.http.Method.GET => app.get_router.resolve(res.request.target, &params),
            std.http.Method.POST => app.post_router.resolve(res.request.target, &params),
            else => null,
        };

        // Build context
        var ctx = Context{
            .req = &res.request,
            .res = res,
            .params = params,
        };
        defer ctx.deinit();

        // Run middleware
        for (app.middleware.items) |mw| {
            mw(&ctx) catch unreachable;
            // Check if middleware terminated the request
            if (ctx.res.state == .finished) {
                return;
            }
        }

        if (handler != null) {
            handler.?(&ctx) catch unreachable;
        } else {
            ctx.res.status = std.http.Status.not_found;
            ctx.text("not found") catch unreachable;
        }
    }
};

test "create an app" {
    var app = try App.init(.{
        .allocator = std.testing.allocator,
    });
    defer app.deinit();
}
