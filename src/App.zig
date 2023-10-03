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
    n_workers: u32 = 16,
    host: []const u8 = "127.0.0.1",
    port: u16 = 3737,
};

const RouterMap = std.AutoHashMap(std.http.Method, *router.RouteTree(Handler));

pub const App = struct {
    allocator: std.mem.Allocator,
    middleware: std.ArrayList(Handler),

    routers: RouterMap,

    server: std.http.Server,
    addr: std.net.Address,
    pool: *std.Thread.Pool,

    pub fn init(opts: Options) !*App {
        var app = try opts.allocator.create(App);

        app.pool = try opts.allocator.create(std.Thread.Pool);
        try app.pool.init(.{
            .allocator = opts.allocator,
            .n_jobs = opts.n_workers,
        });

        app.allocator = opts.allocator;
        app.middleware = std.ArrayList(Handler).init(app.allocator);
        app.addr = try std.net.Address.parseIp4(opts.host, opts.port);

        app.routers = RouterMap.init(opts.allocator);

        app.server = std.http.Server.init(opts.allocator, .{
            .reuse_address = true,
            .reuse_port = true,
        });
        server = app.server;
        return app;
    }

    pub fn deinit(self: *App) void {
        self.server.deinit();
        self.pool.deinit();
        var it = self.routers.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.routers.deinit();
        self.allocator.destroy(self.pool);
        self.allocator.destroy(self);
    }

    // Use adds a Handler function to the app as middleware, so it will run on
    // every request
    pub fn use(app: *App, handler: Handler) !void {
        try app.middleware.append(handler);
    }

    fn addWithMethod(app: *App, m: std.http.Method, path: []const u8, h: Handler) !void {
        if (!app.routers.contains(m)) {
            var tree = try router.RouteTree(Handler).init(app.allocator, "/", null);
            try app.routers.put(m, tree);
        }
        var tree = app.routers.get(m).?;
        try tree.add(path, h);
    }

    fn resolveWithMethod(app: *App, m: std.http.Method, target: []const u8, params: *router.Params) ?Handler {
        var tree = app.routers.get(m);
        if (tree == null) {
            return null;
        }
        return tree.?.resolve(target, params);
    }

    pub fn get(app: *App, path: []const u8, handler: Handler) !void {
        try app.addWithMethod(std.http.Method.GET, path, handler);
    }

    pub fn post(app: *App, path: []const u8, handler: Handler) !void {
        try app.addWithMethod(std.http.Method.POST, path, handler);
    }

    pub fn delete(app: *App, path: []const u8, handler: Handler) !void {
        try app.addWithMethod(std.http.Method.DELETE, path, handler);
    }

    pub fn put(app: *App, path: []const u8, handler: Handler) !void {
        try app.addWithMethod(std.http.Method.PUT, path, handler);
    }

    pub fn patch(app: *App, path: []const u8, handler: Handler) !void {
        try app.addWithMethod(std.http.Method.PATCH, path, handler);
    }

    pub fn head(app: *App, path: []const u8, handler: Handler) !void {
        try app.addWithMethod(std.http.Method.HEAD, path, handler);
    }

    pub fn options(app: *App, path: []const u8, handler: Handler) !void {
        try app.addWithMethod(std.http.Method.OPTIONS, path, handler);
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

        const handler = app.resolveWithMethod(res.request.method, res.request.target, &params);

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

fn testHandler(ctx: *Context) !void {
    try ctx.text("hello");
}

test "create an app" {
    var app = try App.init(.{
        .allocator = std.testing.allocator,
    });
    try app.get("/greet", testHandler);
    defer app.deinit();
}
