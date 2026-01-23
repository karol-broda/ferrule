import { defineConfig, defineDocs, frontmatterSchema, metaSchema } from 'fumadocs-mdx/config';
import { z } from 'zod';
import { ferruleLanguage } from '@ferrule/shiki';

const specFrontmatter = frontmatterSchema.extend({
  status: z.string().optional(),
  version: z.string().optional(),
  last_updated: z.union([z.string(), z.date()]).optional(),
  implemented: z.array(z.string()).optional(),
  pending: z.array(z.string()).optional(),
  deferred: z.array(z.string()).optional(),
});

const rfcFrontmatter = frontmatterSchema.extend({
  rfc: z.union([z.string(), z.number()]).optional(),
  status: z.string().optional(),
  created: z.union([z.string(), z.date()]).optional(),
  target: z.string().optional(),
  depends: z.array(z.union([z.string(), z.number()])).optional(),
});

export const spec = defineDocs({
  dir: '../docs/spec',
  docs: {
    schema: specFrontmatter,
    postprocess: {
      includeProcessedMarkdown: true,
    },
  },
  meta: {
    schema: metaSchema,
  },
});

export const rfcs = defineDocs({
  dir: '../docs/rfcs',
  docs: {
    schema: rfcFrontmatter,
    postprocess: {
      includeProcessedMarkdown: true,
    },
  },
  meta: {
    schema: metaSchema,
  },
});

export default defineConfig({
  mdxOptions: {
    rehypeCodeOptions: {
      themes: {
        light: 'github-light',
        dark: 'github-dark',
      },
      langs: [ferruleLanguage],
      defaultLanguage: 'text',
      lazy: true,
    },
  },
});
