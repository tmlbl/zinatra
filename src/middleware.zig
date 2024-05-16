const std = @import("std");
const context = @import("./Context.zig");

// middleware to parse key-value pairs from the request target and add them to
// the params map in Context.
// If a query string parameter has the same name as a route parameter, or is a
// duplicate, it will be ignored
pub fn queryStringParser(ctx: *context.Context) !void {
    var path = ctx.req.head.target;
    const qix = std.mem.indexOf(u8, path, "?");
    if (qix != null) {
        path = path[1..qix.?];

        // Extract query string parameters
        const query = ctx.req.head.target[qix.? + 1 ..];
        var pairs = std.mem.split(u8, query, "&");
        while (pairs.next()) |pair| {
            const eix = std.mem.indexOf(u8, pair, "=");
            // skip if there is no = character
            if (eix == null) {
                continue;
            }
            const key = pair[0..eix.?];
            const val = pair[eix.? + 1 ..];
            if (ctx.params.get(key) == null) {
                try ctx.params.put(key, val);
            }
        }
    }
}
