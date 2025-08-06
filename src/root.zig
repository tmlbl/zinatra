const zin = @import("./App.zig");

pub const App = zin.App;
pub const Context = @import("./Context.zig");
pub const Handler = zin.Handler;
pub const ErrorHandler = zin.ErrorHandler;

pub const new = zin.new;

pub const Static = @import("./Static.zig");
pub const mw = @import("./middleware.zig");
