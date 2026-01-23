# tree-sitter-ferrule

[Tree-sitter](https://tree-sitter.github.io/tree-sitter/) grammar for the [Ferrule](https://github.com/karol-broda/ferrule) programming language.

## Features

- Full syntax highlighting support
- Code folding
- Indentation
- Local variable tracking
- Code navigation tags
- Text objects for Vim/Helix modes

## Installation

### Neovim (nvim-treesitter)

Add to your nvim-treesitter configuration:

```lua
local parser_config = require("nvim-treesitter.parsers").get_parser_configs()

parser_config.ferrule = {
  install_info = {
    url = "https://github.com/karol-broda/tree-sitter-ferrule",
    files = { "src/parser.c" },
    branch = "main",
  },
  filetype = "ferrule",
}

vim.filetype.add({
  extension = {
    fe = "ferrule",
  },
})
```

Then run `:TSInstall ferrule`.

### Helix

Add to `languages.toml`:

```toml
[[language]]
name = "ferrule"
scope = "source.ferrule"
file-types = ["fe"]
comment-token = "//"
indent = { tab-width = 2, unit = "  " }

[[grammar]]
name = "ferrule"
source = { git = "https://github.com/karol-broda/tree-sitter-ferrule", rev = "main" }
```

Then run `hx --grammar fetch` and `hx --grammar build`.

### Zed

The Ferrule Zed extension includes this grammar automatically.

## Development

### Prerequisites

- Node.js
- Tree-sitter CLI: `npm install -g tree-sitter-cli`

### Building

```bash
# generate the parser
tree-sitter generate

# run tests
tree-sitter test

# parse a file
tree-sitter parse examples/hello.fe
```

### Testing

Test files are in `test/corpus/`. Each test file contains test cases in the format:

```
================================================================================
Test name
================================================================================

source code here

--------------------------------------------------------------------------------

(expected_tree)
```

Run tests with:

```bash
tree-sitter test
```

## Query Files

Query files for editor integration are in the `queries/` directory:

- `highlights.scm` - Syntax highlighting
- `locals.scm` - Local variable/scope tracking
- `tags.scm` - Code navigation (symbols, definitions)
- `indents.scm` - Auto-indentation rules
- `folds.scm` - Code folding regions
- `textobjects.scm` - Text objects for Vim/Helix

## License

MIT

