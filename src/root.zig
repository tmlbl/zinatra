pub const App = @import("./App.zig");

/// Context is important!
pub const Context = @import("./Context.zig");
pub const Handler = App.Handler;
pub const ErrorHandler = App.ErrorHandler;
pub const Static = @import("./Static.zig");
pub const mw = @import("./middleware.zig");

/// Initialize an application
pub fn new(opts: App.Options) !*App {
    return App.init(opts);
}
