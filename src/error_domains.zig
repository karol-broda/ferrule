const std = @import("std");
const types = @import("types.zig");

pub const ErrorDomain = struct {
    name: []const u8,
    variants: []ErrorVariant,

    pub fn findVariant(self: *const ErrorDomain, name: []const u8) ?*const ErrorVariant {
        for (self.variants) |*variant| {
            if (std.mem.eql(u8, variant.name, name)) {
                return variant;
            }
        }
        return null;
    }

    pub fn deinit(self: *const ErrorDomain, allocator: std.mem.Allocator) void {
        for (self.variants) |*variant| {
            variant.deinit(allocator);
        }
        allocator.free(self.variants);
    }
};

pub const ErrorVariant = struct {
    name: []const u8,
    fields: []Field,

    pub fn deinit(self: *const ErrorVariant, allocator: std.mem.Allocator) void {
        for (self.fields) |*field| {
            field.type_annotation.deinit(allocator);
        }
        allocator.free(self.fields);
    }
};

pub const Field = struct {
    name: []const u8,
    type_annotation: types.ResolvedType,
};

pub const ErrorDomainTable = struct {
    domains: std.StringHashMap(ErrorDomain),

    pub fn init(allocator: std.mem.Allocator) ErrorDomainTable {
        return .{
            .domains = std.StringHashMap(ErrorDomain).init(allocator),
        };
    }

    pub fn insert(self: *ErrorDomainTable, name: []const u8, domain: ErrorDomain) !void {
        try self.domains.put(name, domain);
    }

    pub fn get(self: *const ErrorDomainTable, name: []const u8) ?ErrorDomain {
        return self.domains.get(name);
    }

    pub fn deinit(self: *ErrorDomainTable) void {
        var iter = self.domains.valueIterator();
        while (iter.next()) |domain| {
            domain.deinit(self.domains.allocator);
        }
        self.domains.deinit();
    }
};
