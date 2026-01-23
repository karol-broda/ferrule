import type { MDXComponents } from 'mdx/types';

export function getPlainMDXComponents(components?: MDXComponents): MDXComponents {
  return {
    ...components,
  };
}
