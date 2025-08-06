const zin = @import("./App.zig");
const context = @import("./Context.zig");

pub const App = zin.App;
pub const new = zin.new;

pub const Context = context.Context;
pub const Handler = context.Handler;
pub const Error = context.Error;
pub const ErrorHandler = *const fn (*Context, anyerror) anyerror!void;
pub const Static = @import("./Static.zig");

pub const mw = @import("./middleware.zig");
