const std = @import("std");
const context = @import("context.zig");

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

    // compilation context for interning
    // strings are borrowed from the context's arena
    compilation_context: *context.CompilationContext,

    pub fn init(ctx: *context.CompilationContext) SymbolLocationTable {
        return .{
            .symbols = std.StringHashMap(SymbolLocation).init(ctx.permanentAllocator()),
            .allocator = ctx.permanentAllocator(),
            .compilation_context = ctx,
        };
    }

    pub fn deinit(self: *SymbolLocationTable) void {
        // arena cleanup handles string memory; only hashmap and arraylist structures need explicit cleanup
        var iter = self.symbols.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.references.deinit(self.allocator);
        }
        self.symbols.deinit();
    }

    // interns a string in the context's arena
    fn internString(self: *SymbolLocationTable, str: []const u8) ![]const u8 {
        return self.compilation_context.internString(str);
    }

    pub fn addDefinition(self: *SymbolLocationTable, name: []const u8, line: usize, column: usize, length: usize) !void {
        const name_copy = try self.internString(name);

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
            const name_copy = try self.internString(name);
            // note: no errdefer free needed when using interning (arena handles cleanup)

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
