const std = @import("std");
const ferrule = @import("ferrule");
const hover_info = ferrule.hover_info;

pub fn formatHoverContent(allocator: std.mem.Allocator, info: hover_info.HoverInfo) ![]const u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);
    const w = buf.writer(allocator);

    const kind_name = switch (info.kind) {
        .variable => "variable",
        .constant => "constant",
        .parameter => "parameter",
        .function => "function",
        .type_def => "type",
        .error_domain => "error domain",
        .field => "field",
    };

    try w.print("**{s}** _{s}_\n\n", .{ info.name, kind_name });

    if (info.function_info) |func_info| {
        try w.writeAll("```ferrule\n");
        try w.print("function {s}(", .{info.name});

        const param_count = @min(func_info.param_names.len, func_info.params.len);
        for (0..param_count) |i| {
            if (i > 0) try w.writeAll(", ");
            try w.print("{s}: ", .{func_info.param_names[i]});
            try func_info.params[i].format("", .{}, w);
        }

        try w.writeAll(") -> ");
        try func_info.return_type.format("", .{}, w);

        if (func_info.effects.len > 0) {
            try w.writeAll(" with [");
            for (func_info.effects, 0..) |effect, i| {
                if (i > 0) try w.writeAll(", ");
                try w.writeAll(effect.toString());
            }
            try w.writeAll("]");
        }

        if (func_info.error_domain) |domain| {
            try w.print(" use error {s}", .{domain});
        }

        try w.writeAll("\n```\n\n");

        if (func_info.effects.len > 0) {
            try w.writeAll("**Effects:**");
            for (func_info.effects) |effect| {
                try w.print(" `{s}`", .{effect.toString()});
            }
            try w.writeAll("\n\n");
        }

        if (func_info.error_domain) |domain| {
            try w.print("**Error Domain:** `{s}`\n\n", .{domain});
        }
    } else if (info.domain_info) |domain_info| {
        try w.writeAll("```ferrule\n");
        try w.print("domain {s} {{\n", .{info.name});

        for (domain_info.variants) |variant| {
            try w.print("  {s}", .{variant.name});

            if (variant.field_names.len > 0) {
                try w.writeAll(" { ");
                for (variant.field_names, variant.field_types, 0..) |field_name, field_type, i| {
                    if (i > 0) try w.writeAll(", ");
                    try w.print("{s}: ", .{field_name});
                    try field_type.format("", .{}, w);
                }
                try w.writeAll(" }");
            }

            try w.writeAll("\n");
        }

        try w.writeAll("}\n```");
    } else {
        try w.writeAll("```ferrule\n");
        try info.resolved_type.format("", .{}, w);
        try w.writeAll("\n```");
    }

    return buf.toOwnedSlice(allocator);
}
