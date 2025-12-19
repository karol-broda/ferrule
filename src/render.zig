const std = @import("std");

const AnsiColor = struct {
    const reset = "\x1b[0m";
    const bold = "\x1b[1m";
    const dim = "\x1b[2m";
    const italic = "\x1b[3m";
    const underline = "\x1b[4m";
    const red = "\x1b[31m";
    const green = "\x1b[32m";
    const yellow = "\x1b[33m";
    const blue = "\x1b[34m";
    const magenta = "\x1b[35m";
    const cyan = "\x1b[36m";
    const white = "\x1b[37m";
    const gray = "\x1b[90m";
};

const TrueColor = struct {
    const reset = "\x1b[0m";
    const bold = "\x1b[1m";
    const dim = "\x1b[2m";
    const italic = "\x1b[3m";
    const underline = "\x1b[4m";
    const red = "\x1b[38;2;231;130;132m";
    const green = "\x1b[38;2;166;209;137m";
    const yellow = "\x1b[38;2;239;159;118m";
    const blue = "\x1b[38;2;140;170;238m";
    const magenta = "\x1b[38;2;202;158;230m";
    const cyan = "\x1b[38;2;129;200;190m";
    const white = "\x1b[38;2;198;208;245m";
    const gray = "\x1b[38;2;115;121;148m";
};

pub const Theme = struct {
    enabled: bool,
    true_color: bool,

    pub fn init() Theme {
        if (std.process.hasEnvVarConstant("NO_COLOR")) {
            return .{ .enabled = false, .true_color = false };
        }

        const stderr_fd: std.posix.fd_t = std.posix.STDERR_FILENO;
        const stdout_fd: std.posix.fd_t = std.posix.STDOUT_FILENO;
        const is_tty = std.posix.isatty(stderr_fd) or std.posix.isatty(stdout_fd);
        const force_color = std.posix.getenv("FORCE_COLOR") != null;

        if (!is_tty and !force_color) {
            return .{ .enabled = false, .true_color = false };
        }

        const has_true_color = blk: {
            if (std.posix.getenv("COLORTERM")) |colorterm| {
                if (std.mem.eql(u8, colorterm, "truecolor") or std.mem.eql(u8, colorterm, "24bit")) {
                    break :blk true;
                }
            }
            if (std.posix.getenv("TERM")) |term| {
                if (std.mem.indexOf(u8, term, "kitty") != null or
                    std.mem.indexOf(u8, term, "alacritty") != null or
                    std.mem.indexOf(u8, term, "wezterm") != null or
                    std.mem.indexOf(u8, term, "ghostty") != null or
                    std.mem.indexOf(u8, term, "iterm") != null)
                {
                    break :blk true;
                }
            }
            break :blk false;
        };

        return .{ .enabled = true, .true_color = has_true_color };
    }

    pub fn reset(self: Theme) []const u8 {
        if (!self.enabled) return "";
        return if (self.true_color) TrueColor.reset else AnsiColor.reset;
    }

    pub fn bold(self: Theme) []const u8 {
        if (!self.enabled) return "";
        return if (self.true_color) TrueColor.bold else AnsiColor.bold;
    }

    pub fn dim(self: Theme) []const u8 {
        if (!self.enabled) return "";
        return if (self.true_color) TrueColor.gray else AnsiColor.dim;
    }

    pub fn italic(self: Theme) []const u8 {
        if (!self.enabled) return "";
        return if (self.true_color) TrueColor.italic else AnsiColor.italic;
    }

    pub fn underline(self: Theme) []const u8 {
        if (!self.enabled) return "";
        return if (self.true_color) TrueColor.underline else AnsiColor.underline;
    }

    pub fn red(self: Theme) []const u8 {
        if (!self.enabled) return "";
        return if (self.true_color) TrueColor.red else AnsiColor.red;
    }

    pub fn green(self: Theme) []const u8 {
        if (!self.enabled) return "";
        return if (self.true_color) TrueColor.green else AnsiColor.green;
    }

    pub fn yellow(self: Theme) []const u8 {
        if (!self.enabled) return "";
        return if (self.true_color) TrueColor.yellow else AnsiColor.yellow;
    }

    pub fn blue(self: Theme) []const u8 {
        if (!self.enabled) return "";
        return if (self.true_color) TrueColor.blue else AnsiColor.blue;
    }

    pub fn magenta(self: Theme) []const u8 {
        if (!self.enabled) return "";
        return if (self.true_color) TrueColor.magenta else AnsiColor.magenta;
    }

    pub fn cyan(self: Theme) []const u8 {
        if (!self.enabled) return "";
        return if (self.true_color) TrueColor.cyan else AnsiColor.cyan;
    }

    pub fn white(self: Theme) []const u8 {
        if (!self.enabled) return "";
        return if (self.true_color) TrueColor.white else AnsiColor.white;
    }

    pub fn gray(self: Theme) []const u8 {
        if (!self.enabled) return "";
        return if (self.true_color) TrueColor.gray else AnsiColor.gray;
    }
};

pub const Box = struct {
    pub const horizontal = "─";
    pub const vertical = "│";
    pub const top_left = "╭";
    pub const top_right = "╮";
    pub const bottom_left = "╰";
    pub const bottom_right = "╯";
    pub const tee_right = "├";
    pub const tee_left = "┤";
    pub const tee_down = "┬";
    pub const tee_up = "┴";
    pub const cross = "┼";
    pub const arrow_right = "▶";
    pub const arrow_left = "◀";
    pub const bullet = "•";
    pub const check = "✓";
    pub const cross_mark = "✗";
    pub const info = "ℹ";
    pub const warning = "⚠";
};

pub const Renderer = struct {
    writer: std.io.AnyWriter,
    theme: Theme,

    pub fn init(writer: std.io.AnyWriter) Renderer {
        return .{
            .writer = writer,
            .theme = Theme.init(),
        };
    }

    pub fn initWithTheme(writer: std.io.AnyWriter, theme: Theme) Renderer {
        return .{
            .writer = writer,
            .theme = theme,
        };
    }

    pub fn write(self: *Renderer, text: []const u8) !void {
        try self.writer.writeAll(text);
    }

    pub fn print(self: *Renderer, comptime fmt: []const u8, args: anytype) !void {
        try self.writer.print(fmt, args);
    }

    pub fn newline(self: *Renderer) !void {
        try self.writer.writeAll("\n");
    }

    pub fn space(self: *Renderer) !void {
        try self.writer.writeAll(" ");
    }

    pub fn spaces(self: *Renderer, count: usize) !void {
        var i: usize = 0;
        while (i < count) : (i += 1) {
            try self.writer.writeAll(" ");
        }
    }

    pub fn pad(self: *Renderer, width: usize, current: usize) !void {
        if (width > current) {
            try self.spaces(width - current);
        }
    }

    pub fn styled(self: *Renderer, style: []const u8, text: []const u8) !void {
        try self.writer.writeAll(style);
        try self.writer.writeAll(text);
        try self.writer.writeAll(self.theme.reset());
    }

    pub fn styledFmt(self: *Renderer, style: []const u8, comptime fmt: []const u8, args: anytype) !void {
        try self.writer.writeAll(style);
        try self.writer.print(fmt, args);
        try self.writer.writeAll(self.theme.reset());
    }

    pub fn bold(self: *Renderer, text: []const u8) !void {
        try self.styled(self.theme.bold(), text);
    }

    pub fn dim(self: *Renderer, text: []const u8) !void {
        try self.styled(self.theme.dim(), text);
    }

    pub fn red(self: *Renderer, text: []const u8) !void {
        try self.styled(self.theme.red(), text);
    }

    pub fn green(self: *Renderer, text: []const u8) !void {
        try self.styled(self.theme.green(), text);
    }

    pub fn yellow(self: *Renderer, text: []const u8) !void {
        try self.styled(self.theme.yellow(), text);
    }

    pub fn blue(self: *Renderer, text: []const u8) !void {
        try self.styled(self.theme.blue(), text);
    }

    pub fn magenta(self: *Renderer, text: []const u8) !void {
        try self.styled(self.theme.magenta(), text);
    }

    pub fn cyan(self: *Renderer, text: []const u8) !void {
        try self.styled(self.theme.cyan(), text);
    }

    pub fn boldRed(self: *Renderer, text: []const u8) !void {
        try self.writer.writeAll(self.theme.bold());
        try self.writer.writeAll(self.theme.red());
        try self.writer.writeAll(text);
        try self.writer.writeAll(self.theme.reset());
    }

    pub fn boldGreen(self: *Renderer, text: []const u8) !void {
        try self.writer.writeAll(self.theme.bold());
        try self.writer.writeAll(self.theme.green());
        try self.writer.writeAll(text);
        try self.writer.writeAll(self.theme.reset());
    }

    pub fn boldYellow(self: *Renderer, text: []const u8) !void {
        try self.writer.writeAll(self.theme.bold());
        try self.writer.writeAll(self.theme.yellow());
        try self.writer.writeAll(text);
        try self.writer.writeAll(self.theme.reset());
    }

    pub fn boldBlue(self: *Renderer, text: []const u8) !void {
        try self.writer.writeAll(self.theme.bold());
        try self.writer.writeAll(self.theme.blue());
        try self.writer.writeAll(text);
        try self.writer.writeAll(self.theme.reset());
    }

    pub fn boldMagenta(self: *Renderer, text: []const u8) !void {
        try self.writer.writeAll(self.theme.bold());
        try self.writer.writeAll(self.theme.magenta());
        try self.writer.writeAll(text);
        try self.writer.writeAll(self.theme.reset());
    }

    pub fn boldCyan(self: *Renderer, text: []const u8) !void {
        try self.writer.writeAll(self.theme.bold());
        try self.writer.writeAll(self.theme.cyan());
        try self.writer.writeAll(text);
        try self.writer.writeAll(self.theme.reset());
    }

    pub fn gutter(self: *Renderer) !void {
        try self.dim(Box.vertical);
    }

    pub fn gutterTop(self: *Renderer) !void {
        try self.dim(Box.top_left);
        try self.dim(Box.horizontal);
    }

    pub fn gutterBottom(self: *Renderer) !void {
        try self.dim(Box.bottom_left);
        try self.dim(Box.horizontal);
        try self.dim(Box.arrow_right);
    }

    pub fn gutterLine(self: *Renderer, width: usize) !void {
        var i: usize = 0;
        while (i < width) : (i += 1) {
            try self.dim(Box.horizontal);
        }
    }

    pub fn success(self: *Renderer, message: []const u8) !void {
        try self.boldGreen(Box.check);
        try self.space();
        try self.write(message);
        try self.newline();
    }

    pub fn successFmt(self: *Renderer, comptime fmt: []const u8, args: anytype) !void {
        try self.boldGreen(Box.check);
        try self.space();
        try self.print(fmt, args);
        try self.newline();
    }

    pub fn info(self: *Renderer, message: []const u8) !void {
        try self.boldBlue(Box.info);
        try self.space();
        try self.write(message);
        try self.newline();
    }

    pub fn infoFmt(self: *Renderer, comptime fmt: []const u8, args: anytype) !void {
        try self.boldBlue(Box.info);
        try self.space();
        try self.print(fmt, args);
        try self.newline();
    }

    pub fn warn(self: *Renderer, message: []const u8) !void {
        try self.boldYellow(Box.warning);
        try self.space();
        try self.write(message);
        try self.newline();
    }

    pub fn warnFmt(self: *Renderer, comptime fmt: []const u8, args: anytype) !void {
        try self.boldYellow(Box.warning);
        try self.space();
        try self.print(fmt, args);
        try self.newline();
    }

    pub fn fail(self: *Renderer, message: []const u8) !void {
        try self.boldRed(Box.cross_mark);
        try self.space();
        try self.write(message);
        try self.newline();
    }

    pub fn failFmt(self: *Renderer, comptime fmt: []const u8, args: anytype) !void {
        try self.boldRed(Box.cross_mark);
        try self.space();
        try self.print(fmt, args);
        try self.newline();
    }

    pub fn bullet(self: *Renderer, message: []const u8) !void {
        try self.dim(Box.bullet);
        try self.space();
        try self.write(message);
        try self.newline();
    }

    pub fn bulletFmt(self: *Renderer, comptime fmt: []const u8, args: anytype) !void {
        try self.dim(Box.bullet);
        try self.space();
        try self.print(fmt, args);
        try self.newline();
    }

    pub fn header(self: *Renderer, title: []const u8) !void {
        try self.bold(title);
        try self.newline();
        var i: usize = 0;
        while (i < title.len) : (i += 1) {
            try self.dim(Box.horizontal);
        }
        try self.newline();
    }

    pub fn section(self: *Renderer, title: []const u8) !void {
        try self.newline();
        try self.dim("── ");
        try self.bold(title);
        try self.dim(" ──");
        try self.newline();
        try self.newline();
    }

    pub fn keyValue(self: *Renderer, key: []const u8, value: []const u8) !void {
        try self.dim(key);
        try self.write(": ");
        try self.write(value);
        try self.newline();
    }

    pub fn keyValueFmt(self: *Renderer, key: []const u8, comptime fmt: []const u8, args: anytype) !void {
        try self.dim(key);
        try self.write(": ");
        try self.print(fmt, args);
        try self.newline();
    }

    pub fn table(self: *Renderer, comptime headers: []const []const u8, rows: []const []const []const u8, widths: []const usize) !void {
        for (headers, 0..) |h, i| {
            try self.bold(h);
            if (i < headers.len - 1) {
                try self.pad(widths[i], h.len);
                try self.write("  ");
            }
        }
        try self.newline();

        for (widths, 0..) |w, i| {
            var j: usize = 0;
            while (j < w) : (j += 1) {
                try self.dim(Box.horizontal);
            }
            if (i < widths.len - 1) {
                try self.write("  ");
            }
        }
        try self.newline();

        for (rows) |row| {
            for (row, 0..) |cell, i| {
                try self.write(cell);
                if (i < row.len - 1) {
                    try self.pad(widths[i], cell.len);
                    try self.write("  ");
                }
            }
            try self.newline();
        }
    }

    pub fn progressBar(self: *Renderer, current: usize, total: usize, width: usize) !void {
        const filled = if (total > 0) (current * width) / total else 0;
        const empty = width - filled;

        try self.write("[");
        var i: usize = 0;
        while (i < filled) : (i += 1) {
            try self.green("█");
        }
        i = 0;
        while (i < empty) : (i += 1) {
            try self.dim("░");
        }
        try self.write("]");
        try self.print(" {d}/{d}", .{ current, total });
    }
};

pub fn countDigits(n: usize) usize {
    if (n == 0) return 1;
    var count: usize = 0;
    var num = n;
    while (num > 0) : (num /= 10) {
        count += 1;
    }
    return count;
}

pub fn getLine(source: []const u8, target_line: usize) ?[]const u8 {
    var line: usize = 1;
    var start: usize = 0;
    var i: usize = 0;

    while (i < source.len) : (i += 1) {
        if (source[i] == '\n') {
            if (line == target_line) {
                return source[start..i];
            }
            line += 1;
            start = i + 1;
        }
    }

    if (line == target_line) {
        return source[start..];
    }

    return null;
}
