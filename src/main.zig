const std = @import("std");

const router = @import("./route_tree.zig");
const types = @import("./types.zig");
pub const Handler = types.Handler;

pub const Request = std.http.Server.Request;
pub const Response = std.http.Server.Response;

pub const App = struct {
    allocator: std.mem.Allocator,
    router: router.RouteTable,

    pub fn get(app: *App, path: []const u8, handler: Handler) void {
        _ = app;
        _ = handler;
        _ = path;
    }
};

pub fn new(a: std.mem.Allocator) !App {
    return App{
        .allocator = a,
        .router = try router.RouteTable.init(a),
    };
}
