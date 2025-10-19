# Ferrule LSP Setup Guide

This guide explains how to set up and use the Ferrule Language Server with VS Code.

## Components

1. **Ferrule LSP Server** (`ferrule-lsp`) - A Zig-based language server that:
   - Parses `.fe` files using the existing lexer and parser
   - Runs semantic analysis (type checking, error checking, effect checking)
   - Converts diagnostics to LSP format
   - Communicates via JSON-RPC over stdin/stdout

2. **VS Code Extension** - Provides:
   - Syntax highlighting via TextMate grammar
   - LSP client that spawns and communicates with the server
   - Inline diagnostic display

## Build Instructions

### 1. Build the LSP Server

```bash
cd /home/karolbroda/personal/ferrule
zig build
```

This creates `/home/karolbroda/personal/ferrule/zig-out/bin/ferrule-lsp`

### 2. Build the VS Code Extension

```bash
cd /home/karolbroda/personal/ferrule/vscode-ferrule
npm install  # or bun install
npm run compile
```

## Installation

### Option A: Development Mode (Recommended for Testing)

1. Open the `vscode-ferrule` directory in VS Code
2. Press F5 to launch a new VS Code window with the extension loaded
3. Open a `.fe` file to test

### Option B: Package and Install

```bash
cd /home/karolbroda/personal/ferrule/vscode-ferrule
npm run package  # Creates ferrule-0.1.0.vsix
code --install-extension ferrule-0.1.0.vsix
```

## Configuration

The extension looks for the LSP server in the following order:

1. `ferrule.lspPath` setting (if configured)
2. `<workspace>/zig-out/bin/ferrule-lsp`
3. `ferrule-lsp` in PATH

To configure manually, add to VS Code settings:

```json
{
  "ferrule.lspPath": "/path/to/ferrule-lsp",
  "ferrule.trace.server": "verbose"  // For debugging
}
```

## Testing

1. Create a test file `test.fe`:

```ferrule
package example.test;

domain TestError {
  Invalid { msg: String }
}

use error TestError;

function greet(name: String) -> String {
  return "Hello, " + name;
}

function main() -> i32 {
  const result = greet("World");
  return 0;
}
```

2. Open the file in VS Code
3. You should see:
   - Syntax highlighting
   - Diagnostics for any errors
   - The LSP server running in the background

## Troubleshooting

### LSP Server Not Starting

- Check the Output panel (View → Output → Ferrule Language Server)
- Verify the LSP binary path: `which ferrule-lsp` or check workspace path
- Enable trace logging: `"ferrule.trace.server": "verbose"`

### Syntax Highlighting Not Working

- Ensure the file has `.fe` extension
- Check if the extension is activated: look for "Ferrule" in the bottom-right corner

### Diagnostics Not Appearing

- Open the Developer Console (Help → Toggle Developer Tools)
- Look for errors in the Console tab
- Check the LSP communication in the Output panel

## Features

✅ **Syntax Highlighting**
- Keywords (function, const, var, if, else, etc.)
- Types (i32, String, Bool, etc.)
- String literals and escape sequences
- Comments (line and block)
- Operators

✅ **Diagnostics**
- Type errors
- Undefined variables/functions
- Effect checking errors
- Error domain violations
- Region/lifetime errors
- Exhaustiveness checking

✅ **Real-time Analysis**
- Diagnostics update as you type
- Full semantic analysis on every change

## Architecture

```
VS Code Extension (TypeScript)
    ↓ (spawns process)
Ferrule LSP Server (Zig)
    ├─ Lexer
    ├─ Parser
    └─ Semantic Analyzer
        ├─ Declaration Pass
        ├─ Type Resolver
        ├─ Type Checker
        ├─ Effect Checker
        ├─ Error Checker
        ├─ Region Checker
        └─ Exhaustiveness Checker
    ↓ (JSON-RPC over stdio)
VS Code Client
    └─ Display diagnostics inline
```

## File Structure

```
ferrule/
├── src/
│   ├── lsp_server.zig          # Main LSP server implementation
│   ├── lexer.zig               # Lexer
│   ├── parser.zig              # Parser
│   ├── semantic.zig            # Semantic analyzer
│   └── diagnostics.zig         # Diagnostic system
├── vscode-ferrule/
│   ├── src/
│   │   └── extension.ts        # Extension entry point
│   ├── syntaxes/
│   │   └── ferrule.tmLanguage.json  # Syntax highlighting
│   ├── package.json            # Extension manifest
│   └── tsconfig.json           # TypeScript config
└── build.zig                   # Build configuration
```

## LSP Protocol Support

Currently implemented:

- `initialize` - Server capabilities
- `initialized` - Initialization complete
- `shutdown` - Graceful shutdown
- `exit` - Terminate server
- `textDocument/didOpen` - Document opened
- `textDocument/didChange` - Document changed
- `textDocument/didClose` - Document closed
- `textDocument/publishDiagnostics` - Send diagnostics to client

## Future Enhancements

Potential features to add:

- [ ] Go to definition
- [ ] Find references
- [ ] Hover documentation
- [ ] Code completion
- [ ] Rename symbol
- [ ] Document symbols
- [ ] Workspace symbols
- [ ] Code actions (quick fixes)
- [ ] Formatting
- [ ] Signature help

## Contributing

To extend the LSP server:

1. Add new protocol handlers in `src/lsp_server.zig`
2. Update capabilities in `handleInitialize`
3. Rebuild: `zig build`
4. Test in VS Code

To extend the extension:

1. Modify `vscode-ferrule/src/extension.ts`
2. Update `package.json` if adding new features
3. Recompile: `npm run compile`
4. Reload the extension window (F5 or Cmd+R in debug window)

## License

Same as the Ferrule project.

