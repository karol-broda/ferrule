# @ferrule/shiki

Shiki syntax highlighting support for the Ferrule programming language.

## Installation

```bash
npm install @ferrule/shiki shiki
# or
bun add @ferrule/shiki shiki
# or
pnpm add @ferrule/shiki shiki
```

## Usage

```typescript
import { codeToHtml } from 'shiki';
import { ferruleLanguage } from '@ferrule/shiki';

const html = await codeToHtml(
  `function main() -> i32 {
    return 42;
  }`,
  {
    lang: ferruleLanguage,
    theme: 'github-dark'
  }
);
```

Or register it globally:

```typescript
import { getHighlighter } from 'shiki';
import { ferruleLanguage } from '@ferrule/shiki';

const highlighter = await getHighlighter({
  themes: ['github-dark'],
  langs: [ferruleLanguage]
});

const html = highlighter.codeToHtml(
  `function main() -> i32 {
    return 42;
  }`,
  { lang: 'ferrule', theme: 'github-dark' }
);
```

## Direct Grammar Access

You can also import the TextMate grammar directly:

```typescript
import grammar from '@ferrule/grammar';
```

## License

GPL-3.0-or-later - See [LICENSE](../../LICENSE) in the main repository.

