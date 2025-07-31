const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cInclude("openssl/ssl.h");
});

const router = @import("./RouteTree.zig");
const Context = @import("./Context.zig");
pub const Handler = *const fn (*Context) anyerror!void;

pub const ErrorHandler = *const fn (*Context, anyerror) anyerror!void;

var handle_requests = true;

pub const Options = struct {
    allocator: std.mem.Allocator = std.heap.page_allocator,
    n_workers: usize = 0,
    host: []const u8 = "0.0.0.0",
    port: u16 = 3737,
    errorHandler: ErrorHandler = defaultErrorHandler,
};

pub fn new(opts: Options) !*App {
    return App.init(opts);
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

const RouterMap = std.AutoHashMap(std.http.Method, *router.RouteTree(Handler));

pub const App = struct {
    allocator: std.mem.Allocator,
    pre_middleware: std.ArrayList(Handler),
    post_middleware: std.ArrayList(Handler),
    errorHandler: ErrorHandler,
    listener: std.net.Server,

    routers: RouterMap,

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

    fn setUpListener(self: *App) !void {
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
        std.log.debug("listener started on {}", .{self.addr});
    }

    pub fn listen(self: *App) !void {
        try self.setUpListener();

        std.log.debug("starting {} workers", .{self.n_workers});
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
        const readBuf = try self.allocator.alloc(u8, 8192);
        defer self.allocator.free(readBuf);

        while (handle_requests) {
            const conn = try self.listener.accept();

            var server = std.http.Server.init(conn, readBuf);
            var req = try server.receiveHead();
            handleRequest(self, &req);

            conn.stream.close();
        }
    }

    pub fn listenTls(self: *App, certPath: []const u8, keyPath: []const u8) !void {
        const settings = c.OPENSSL_INIT_new();
        if (settings == null) {
            return error.SSL_NULL_SETTINGS;
        }

        const ret = c.OPENSSL_init_ssl(0, settings.?);
        if (ret != 1) {
            return error.SSL_INIT_FAILED;
        }

        const method = c.TLS_server_method();
        if (method == null) {
            return error.NoMethod;
        }
        const ctx = c.SSL_CTX_new(method.?);
        if (ctx == null) {
            return error.CreateContextFailed;
        }

        // Load cert and key
        const certPathZ = try std.fmt.allocPrintZ(self.allocator, "{s}", .{certPath});
        if (c.SSL_CTX_use_certificate_file(ctx, certPathZ.ptr, c.SSL_FILETYPE_PEM) <= 0) {
            return error.CertificateLoadFailed;
        }

        const keyPathZ = try std.fmt.allocPrintZ(self.allocator, "{s}", .{keyPath});
        if (c.SSL_CTX_use_PrivateKey_file(ctx, keyPathZ.ptr, c.SSL_FILETYPE_PEM) <= 0) {
            return error.KeyLoadFailed;
        }

        try self.setUpListener();
        std.log.debug("starting {} workers", .{self.n_workers});
        var threads = std.ArrayList(std.Thread).init(self.allocator);
        for (0..self.n_workers) |_| {
            const t = try std.Thread.spawn(.{}, App.runServerTls, .{ self, ctx });
            try threads.append(t);
        }
        for (threads.items) |t| {
            t.join();
        }
    }

    fn runServerTls(self: *App, ctx: ?*c.SSL_CTX) !void {
        const readBuf = try self.allocator.alloc(u8, 8192);
        defer self.allocator.free(readBuf);

        while (handle_requests) {
            var conn = try self.listener.accept();

            const realSock = conn.stream.handle;

            var sv: [2]std.c.fd_t = undefined;
            if (std.c.socketpair(std.c.AF.UNIX, std.c.SOCK.STREAM, 0, &sv) == -1) {
                return error.SockPairFailed;
            }

            conn.stream.handle = sv[1];

            const ssl = c.SSL_new(ctx);
            if (ssl == null) {
                std.log.err("ssl new failed", .{});
                conn.stream.close();
                continue;
            }

            _ = c.SSL_set_fd(ssl, realSock);
            if (c.SSL_accept(ssl) != 1) {
                std.log.err("ssl accept failed", .{});
                c.SSL_free(ssl);
                conn.stream.close();
                continue;
            }

            const pid = try std.posix.fork();
            if (pid == 0) {
                const buf = try self.allocator.alloc(u8, 4096);
                defer self.allocator.free(buf);

                const bufLen: c_int = @intCast(buf.len);

                var pollFds = try self.allocator.alloc(std.posix.pollfd, 2);
                pollFds[0] = std.posix.pollfd{
                    .fd = realSock,
                    .events = std.posix.POLL.IN,
                    .revents = 0,
                };
                pollFds[1] = std.posix.pollfd{
                    .fd = sv[0],
                    .events = std.posix.POLL.IN,
                    .revents = 0,
                };

                while (true) {
                    _ = try std.posix.poll(pollFds, 10);

                    if ((pollFds[0].revents & std.posix.POLL.IN) != 0) {
                        const read = c.SSL_read(ssl, buf.ptr, bufLen);
                        if (read <= 0) {
                            continue;
                        }
                        _ = try std.posix.write(sv[0], buf[0..@intCast(read)]);
                    }

                    if ((pollFds[1].revents & std.posix.POLL.IN) != 0) {
                        const read = try std.posix.read(sv[0], buf);
                        if (read == 0) {
                            break;
                        }
                        const written = c.SSL_write(ssl, buf.ptr, @intCast(read));
                        if (written <= 0) {
                            break;
                        }
                    }
                }

                if (c.SSL_shutdown(ssl) != 1) {
                    std.log.err("ssl shutdown failed", .{});
                }
                c.SSL_free(ssl);
            } else {
                var server = std.http.Server.init(conn, readBuf);
                var req = try server.receiveHead();
                handleRequest(self, &req);
            }
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

        ctx.headers.append(.{
            .name = "Connection",
            .value = "close",
        }) catch unreachable;

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
            ctx.text(.not_found, "not found") catch unreachable;
        }

        for (app.post_middleware.items) |m| {
            m(&ctx) catch |e| {
                app.errorHandler(&ctx, e) catch unreachable;
            };
        }
    }
};

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
