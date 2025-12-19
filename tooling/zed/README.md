# Ferrule for Zed

Ferrule language support for the [Zed](https://zed.dev) editor.

## Features

- Syntax highlighting
- Bracket matching
- Auto-indentation
- Code outline
- Vim text objects support
- LSP integration (ferrule-lsp)

## Installation

### Manual Installation (Development)

1. Clone this repository to your Zed extensions directory:
   ```bash
   # macOS
   ln -s /path/to/ferrule/tooling/zed ~/.config/zed/extensions/ferrule
   
   # Linux
   ln -s /path/to/ferrule/tooling/zed ~/.config/zed/extensions/ferrule
   ```

2. Reload Zed

## Requirements

### Tree-sitter Grammar

This extension requires the `tree-sitter-ferrule` grammar. The grammar is fetched automatically from:

```
https://github.com/karolbroda/tree-sitter-ferrule
```

### Language Server (Optional)

For full IDE features, install the Ferrule LSP:

```bash
# build from the ferrule repository
zig build
# the lsp binary is at zig-out/bin/ferrule-lsp
```

Then configure Zed to use it by adding to your settings:

```json
{
  "lsp": {
    "ferrule-lsp": {
      "binary": {
        "path": "/path/to/ferrule/zig-out/bin/ferrule-lsp"
      }
    }
  }
}
```

## File Types

- `.fe` - Ferrule source files

## License

Apache-2.0
