# Ferrule Language Support for VS Code

This extension provides language support for the Ferrule programming language

## Requirements

The Ferrule LSP server (`ferrule-lsp`) must be built and available. The extension will automatically look for it in:

1. The path specified in `ferrule.lspPath` setting
2. `zig-out/bin/ferrule-lsp` in your workspace
3. `ferrule-lsp` in your PATH

## Building

1. Build the LSP server:
   ```bash
   cd /path/to/ferrule
   zig build
   ```

2. Install extension dependencies:
   ```bash
   cd vscode-ferrule
   bun install
   ```

3. Compile the extension:
   ```bash
   bun run compile
   ```

4. Package the extension (optional):
   ```bash
   bun run package
   ```

## Installation

### Development
1. Open the `vscode-ferrule` directory in VS Code
2. Press F5 to launch a new VS Code window with the extension loaded
---
or use the `launch.json` and select the `Run Extension` launch target

### Production
1. Package the extension: `bun run package`
2. Install the `.vsix` file: `code --install-extension ferrule-0.1.0.vsix`

## Configuration

- `ferrule.lspPath`: Path to the Ferrule LSP server executable
- `ferrule.trace.server`: Enable LSP communication tracing (off, messages, verbose)

## Development

To work on this extension:

1. Open in VS Code
2. Run `bun install` to install dependencies
3. Press F5 to start debugging
4. Make changes and reload the extension window

