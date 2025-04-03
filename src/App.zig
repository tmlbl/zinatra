const std = @import("std");
const builtin = @import("builtin");

const router = @import("./RouteTree.zig");
const context = @import("./Context.zig");
pub const mw = @import("./middleware.zig");

pub const Context = context.Context;
pub const Handler = context.Handler;
pub const ErrorHandler = *const fn (*Context, anyerror) anyerror!void;
pub const Static = @import("./Static.zig");

var handle_requests = true;

pub const Options = struct {
    allocator: std.mem.Allocator,
    n_workers: usize = 0,
    host: []const u8 = "0.0.0.0",
    port: u16 = 3737,
    errorHandler: ErrorHandler = defaultErrorHandler,
};

fn defaultErrorHandler(ctx: *Context, err: anyerror) !void {
    const msg = try std.fmt.allocPrint(
        ctx.allocator(),
        "internal error: {any}",
        .{err},
    );
    try ctx.statusText(std.http.Status.internal_server_error, msg);
}

const RouterMap = std.AutoHashMap(std.http.Method, *router.RouteTree(Handler));

pub const App = struct {
    allocator: std.mem.Allocator,
    pre_middleware: std.ArrayList(Handler),
    post_middleware: std.ArrayList(Handler),
    errorHandler: ErrorHandler,
    listener: std.net.Server,

    routers: RouterMap,

    read_buffer: []u8,
    addr: std.net.Address,
    n_workers: usize = 1,

    pub fn init(opts: Options) !*App {
        var app = try opts.allocator.create(App);

        app.allocator = opts.allocator;
        app.pre_middleware = std.ArrayList(Handler).init(app.allocator);
        app.post_middleware = std.ArrayList(Handler).init(app.allocator);
        app.errorHandler = opts.errorHandler;
        app.addr = try std.net.Address.parseIp4(opts.host, opts.port);
        app.n_workers = opts.n_workers;
        if (app.n_workers == 0) {
            app.n_workers = try std.Thread.getCpuCount();
        }

        app.routers = RouterMap.init(opts.allocator);

        app.read_buffer = try app.allocator.alloc(u8, 4096);

        return app;
    }

    pub fn deinit(self: *App) void {
        self.allocator.free(self.read_buffer);
        var it = self.routers.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.routers.deinit();
        self.allocator.destroy(self);
    }

    // Use adds a Handler function to the app as middleware, so it will run on
    // every request
    pub fn use(app: *App, handler: Handler) !void {
        try app.pre_middleware.append(handler);
    }

    pub fn after(app: *App, handler: Handler) !void {
        try app.post_middleware.append(handler);
    }

    fn addWithMethod(app: *App, m: std.http.Method, path: []const u8, h: Handler) !void {
        if (!app.routers.contains(m)) {
            const tree = try router.RouteTree(Handler).init(app.allocator, "/", null);
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
        if (builtin.target.os.tag == .linux) {
            _ = std.os.linux.sigaction(std.os.linux.SIG.INT, &.{
                .handler = .{ .handler = &App.onSigint },
                .mask = std.os.linux.empty_sigset,
                .flags = (std.os.linux.SA.SIGINFO | std.os.linux.SA.RESTART),
            }, null);
        }

        self.listener = try self.addr.listen(.{
            .reuse_address = true,
        });
        std.log.debug("listening on {}...", .{self.addr});

        self.read_buffer = try self.allocator.alloc(u8, 4096);

        var threads = std.ArrayList(std.Thread).init(self.allocator);
        for (0..self.n_workers) |_| {
            const t = try std.Thread.spawn(.{}, App.runServer, .{self});
            try threads.append(t);
        }
        for (threads.items) |t| {
            t.join();
        }
    }

    fn runServer(self: *App) !void {
        while (handle_requests) {
            const conn = try self.listener.accept();
            var server = std.http.Server.init(conn, self.read_buffer);
            var req = try server.receiveHead();
            handleRequest(self, &req);
        }
    }

    fn onSigint(_: c_int) callconv(.C) void {
        std.os.linux.exit_group(0);
    }

    fn handleRequest(app: *App, req: *std.http.Server.Request) void {
        var params = std.StringHashMap([]const u8).init(app.allocator);

        const handler = app.resolveWithMethod(req.head.method, req.head.target, &params);

        // Build context
        var arena = std.heap.ArenaAllocator.init(app.allocator);
        var ctx = Context{
            .arena = arena,
            .req = req,
            .params = params,
            .headers = std.ArrayList(std.http.Header).init(arena.allocator()),
        };
        defer ctx.deinit();

        // Run middleware
        for (app.pre_middleware.items) |m| {
            m(&ctx) catch |e| {
                app.errorHandler(&ctx, e) catch unreachable;
            };
            // Check if middleware terminated the request
            if (ctx.req.server.state == .ready) {
                return;
            }
        }

        if (handler != null) {
            handler.?(&ctx) catch |e| {
                app.errorHandler(&ctx, e) catch unreachable;
            };
        } else {
            ctx.statusText(std.http.Status.not_found, "not found") catch unreachable;
        }

        for (app.post_middleware.items) |m| {
            m(&ctx) catch |e| {
                app.errorHandler(&ctx, e) catch unreachable;
            };
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
    defer app.deinit();
    try app.get("/greet", testHandler);
}
