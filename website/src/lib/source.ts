import { spec, rfcs } from 'fumadocs-mdx:collections/server';
import { type InferPageType, loader } from 'fumadocs-core/source';

export const specSource = loader({
  baseUrl: '/spec',
  source: spec.toFumadocsSource(),
});

export const rfcsSource = loader({
  baseUrl: '/rfcs',
  source: rfcs.toFumadocsSource(),
});

export function getSpecPageImage(page: InferPageType<typeof specSource>) {
  const segments = [...page.slugs, 'image.png'];

  return {
    segments,
    url: `/og/spec/${segments.join('/')}`,
  };
}

export function getRfcPageImage(page: InferPageType<typeof rfcsSource>) {
  const segments = [...page.slugs, 'image.png'];

  return {
    segments,
    url: `/og/rfcs/${segments.join('/')}`,
  };
}

export async function getSpecLLMText(page: InferPageType<typeof specSource>) {
  const processed = await page.data.getText('processed');

  return `# ${page.data.title}

${processed}`;
}

export async function getRfcLLMText(page: InferPageType<typeof rfcsSource>) {
  const processed = await page.data.getText('processed');

  return `# ${page.data.title}

${processed}`;
}
