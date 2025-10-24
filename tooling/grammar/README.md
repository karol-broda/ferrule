# @ferrule/grammar

TextMate grammar definition for the Ferrule programming language.

## Installation

```bash
npm install @ferrule/grammar
# or
bun add @ferrule/grammar
# or
pnpm add @ferrule/grammar
```

## Usage

This package exports a TextMate grammar JSON file that can be used with any editor or tool that supports TextMate grammars.

```typescript
import grammar from '@ferrule/grammar';

console.log(grammar.scopeName); // 'source.ferrule'
console.log(grammar.patterns);
```

## Use Cases

- **Syntax Highlighting**: Use with Shiki, Prism, or other syntax highlighters
- **Editor Support**: Integrate with VS Code, Sublime Text, or other editors
- **Code Analysis**: Build tools that need to parse Ferrule code

## Related Packages

- [`@ferrule/shiki`](https://www.npmjs.com/package/@ferrule/shiki) - Shiki integration for Ferrule

## License

GPL-3.0-or-later - See [LICENSE](../../LICENSE) in the main repository.

