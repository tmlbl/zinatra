const App = @This();

allocator: std.mem.Allocator,
pre_middleware: std.ArrayList(Handler),
post_middleware: std.ArrayList(Handler),
errorHandler: ErrorHandler,
listener: std.net.Server,

routers: RouterMap,

addr: std.net.Address,
n_workers: usize = 1,

pub const Options = struct {
    allocator: std.mem.Allocator = std.heap.page_allocator,
    n_workers: usize = 0,
    host: []const u8 = "0.0.0.0",
    port: u16 = 3737,
    errorHandler: ErrorHandler = defaultErrorHandler,
};

pub fn init(opts: Options) !*App {
    var app = try opts.allocator.create(App);

    app.allocator = opts.allocator;
    app.pre_middleware = try std.ArrayList(Handler).initCapacity(app.allocator, 128);
    app.post_middleware = try std.ArrayList(Handler).initCapacity(app.allocator, 64);
    app.errorHandler = opts.errorHandler;
    app.addr = try std.net.Address.parseIp4(opts.host, opts.port);
    app.n_workers = opts.n_workers;
    if (app.n_workers == 0) {
        app.n_workers = try std.Thread.getCpuCount() * 2;
    }

    app.routers = RouterMap.init(opts.allocator);

    return app;
}

pub fn deinit(self: *App) void {
    var it = self.routers.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.*.deinit();
    }
    self.routers.deinit();
    self.pre_middleware.deinit(self.allocator);
    self.post_middleware.deinit(self.allocator);
    self.allocator.destroy(self);
}

/// Add a Handler function as middleware. Middleware handlers will be called for every
/// request, in the order they are added, and before the route handlers.
///
/// Middleware can terminate a request before it reaches the route handlers by sending
/// a response, i.e.
///
/// fn auth(ctx: *zin.Context) !void {
///     const authorization = try ctx.getHeader("Authorization");
///     if (authorization.len == 0) {
///         try ctx.text(.unauthorized, "missing authorization header");
///     }
/// }
pub fn use(app: *App, handler: Handler) !void {
    try app.pre_middleware.appendBounded(handler);
}

/// After is like use, but for middleware that runs after a request has completed.
/// Useful for things like logging and metrics.
pub fn after(app: *App, handler: Handler) !void {
    try app.post_middleware.appendBounded(handler);
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

/// Register a Handler for the GET method
pub fn get(app: *App, path: []const u8, handler: Handler) !void {
    try app.addWithMethod(std.http.Method.GET, path, handler);
}

/// Register a Handler for the POST method
pub fn post(app: *App, path: []const u8, handler: Handler) !void {
    try app.addWithMethod(std.http.Method.POST, path, handler);
}

/// Register a Handler for the DELETE method
pub fn delete(app: *App, path: []const u8, handler: Handler) !void {
    try app.addWithMethod(std.http.Method.DELETE, path, handler);
}

/// Register a Handler for the PUT method
pub fn put(app: *App, path: []const u8, handler: Handler) !void {
    try app.addWithMethod(std.http.Method.PUT, path, handler);
}

/// Register a Handler for the PATCH method
pub fn patch(app: *App, path: []const u8, handler: Handler) !void {
    try app.addWithMethod(std.http.Method.PATCH, path, handler);
}

/// Register a Handler for the HEAD method
pub fn head(app: *App, path: []const u8, handler: Handler) !void {
    try app.addWithMethod(std.http.Method.HEAD, path, handler);
}

/// Register a Handler for the OPTIONS method
pub fn options(app: *App, path: []const u8, handler: Handler) !void {
    try app.addWithMethod(std.http.Method.OPTIONS, path, handler);
}

/// Start the application
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
    std.log.debug("listener started on port {d}", .{self.addr.getPort()});

    std.log.debug("starting {} workers", .{self.n_workers});
    var threads = try std.ArrayList(std.Thread).initCapacity(
        self.allocator,
        self.n_workers,
    );
    for (0..self.n_workers) |_| {
        const t = try std.Thread.spawn(.{}, App.runServer, .{self});
        threads.appendAssumeCapacity(t);
    }
    for (threads.items) |t| {
        t.join();
    }
}

fn runServer(self: *App) !void {
    const readBuf = try self.allocator.alloc(u8, 8192);
    defer self.allocator.free(readBuf);

    const writeBuf = try self.allocator.alloc(u8, 8192);
    defer self.allocator.free(writeBuf);

    while (true) {
        var conn = try self.listener.accept();
        var reader = conn.stream.reader(readBuf);
        var writer = conn.stream.writer(writeBuf);

        var server = std.http.Server.init(reader.interface(), &writer.interface);
        var req = try server.receiveHead();
        handleRequest(self, &req);

        conn.stream.close();
    }
}

fn onSigint(_: c_int) callconv(.C) void {
    std.os.linux.exit_group(0);
}

fn handleRequest(app: *App, req: *std.http.Server.Request) void {
    var params = std.StringHashMap([]const u8).init(app.allocator);

    const handler: ?Handler = app.resolveWithMethod(req.head.method, req.head.target, &params);

    // Build context
    var arena = std.heap.ArenaAllocator.init(app.allocator);
    var ctx = Context.init(&arena, req, params) catch unreachable;
    defer ctx.deinit();

    ctx.headers.appendBounded(.{
        .name = "Connection",
        .value = "close",
    }) catch unreachable;

    // Run middleware
    for (app.pre_middleware.items) |m| {
        m(&ctx) catch |e| {
            app.errorHandler(&ctx, e) catch unreachable;
        };
        // Check if middleware terminated the request
        if (ctx.req.server.out.end > 0) {
            return;
        }
    }

    if (handler != null) {
        handler.?(&ctx) catch |e| {
            app.errorHandler(&ctx, e) catch unreachable;
        };
    } else {
        ctx.text(.not_found, "not found") catch unreachable;
    }

    for (app.post_middleware.items) |m| {
        m(&ctx) catch |e| {
            app.errorHandler(&ctx, e) catch unreachable;
        };
    }
}

fn testHandler(ctx: *Context) !void {
    try ctx.text(.ok, "hello");
}

test "create an app" {
    var app = try App.init(.{
        .allocator = std.testing.allocator,
    });
    defer app.deinit();
    try app.get("/greet", testHandler);
}

fn defaultErrorHandler(ctx: *Context, err: anyerror) !void {
    switch (err) {
        Context.Error.ParseError => {
            const msg = try std.fmt.allocPrint(
                ctx.allocator(),
                "failed to parse body",
                .{},
            );
            try ctx.text(.bad_request, msg);
            return;
        },
        else => {
            const msg = try std.fmt.allocPrint(
                ctx.allocator(),
                "internal error: {any}",
                .{err},
            );
            try ctx.text(.internal_server_error, msg);
        },
    }
}

const std = @import("std");
const builtin = @import("builtin");

const router = @import("./RouteTree.zig");
const Context = @import("./Context.zig");

pub const Handler = *const fn (*Context) anyerror!void;
pub const ErrorHandler = *const fn (*Context, anyerror) anyerror!void;
const RouterMap = std.AutoHashMap(std.http.Method, *router.RouteTree(Handler));
