const std = @import("std");

pub const LocationInfo = struct {
    line: usize,
    column: usize,
    length: usize,
};

pub const SymbolLocation = struct {
    name: []const u8,
    definition: LocationInfo,
    references: std.ArrayList(LocationInfo),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *SymbolLocation) void {
        self.allocator.free(self.name);
        self.references.deinit(self.allocator);
    }
};

pub const SymbolLocationTable = struct {
    symbols: std.StringHashMap(SymbolLocation),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SymbolLocationTable {
        return .{
            .symbols = std.StringHashMap(SymbolLocation).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SymbolLocationTable) void {
        var iter = self.symbols.iterator();
        while (iter.next()) |entry| {
            var symbol = entry.value_ptr;
            symbol.deinit();
        }
        self.symbols.deinit();
    }

    pub fn addDefinition(self: *SymbolLocationTable, name: []const u8, line: usize, column: usize, length: usize) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);

        const symbol = SymbolLocation{
            .name = name_copy,
            .definition = .{
                .line = line,
                .column = column,
                .length = length,
            },
            .references = std.ArrayList(LocationInfo){},
            .allocator = self.allocator,
        };

        try self.symbols.put(name_copy, symbol);
    }

    pub fn addReference(self: *SymbolLocationTable, name: []const u8, line: usize, column: usize, length: usize) !void {
        if (self.symbols.getPtr(name)) |symbol| {
            try symbol.references.append(self.allocator, .{
                .line = line,
                .column = column,
                .length = length,
            });
        } else {
            const name_copy = try self.allocator.dupe(u8, name);
            errdefer self.allocator.free(name_copy);

            var symbol = SymbolLocation{
                .name = name_copy,
                .definition = .{ .line = 0, .column = 0, .length = 0 },
                .references = std.ArrayList(LocationInfo){},
                .allocator = self.allocator,
            };

            try symbol.references.append(self.allocator, .{
                .line = line,
                .column = column,
                .length = length,
            });

            try self.symbols.put(name_copy, symbol);
        }
    }

    pub fn findSymbolAt(self: *const SymbolLocationTable, line: usize, col: usize) ?[]const u8 {
        var iter = self.symbols.iterator();
        while (iter.next()) |entry| {
            const symbol = entry.value_ptr;

            if (symbol.definition.line == line and
                col >= symbol.definition.column and
                col < symbol.definition.column + symbol.definition.length)
            {
                return symbol.name;
            }

            for (symbol.references.items) |ref| {
                if (ref.line == line and
                    col >= ref.column and
                    col < ref.column + ref.length)
                {
                    return symbol.name;
                }
            }
        }
        return null;
    }

    pub fn getDefinition(self: *const SymbolLocationTable, name: []const u8) ?LocationInfo {
        if (self.symbols.get(name)) |symbol| {
            if (symbol.definition.length > 0) {
                return symbol.definition;
            }
        }
        return null;
    }

    pub fn getReferences(self: *const SymbolLocationTable, name: []const u8) ?[]const LocationInfo {
        if (self.symbols.get(name)) |symbol| {
            return symbol.references.items;
        }
        return null;
    }
};
