import { getSpecLLMText, specSource } from '@/lib/source';
import { notFound } from 'next/navigation';

export const revalidate = false;

export async function GET(_req: Request, { params }: { params: Promise<{ slug?: string[] }> }) {
  const { slug } = await params;
  const page = specSource.getPage(slug);
  if (page === null || page === undefined) notFound();

  return new Response(await getSpecLLMText(page), {
    headers: {
      'Content-Type': 'text/markdown',
    },
  });
}

export function generateStaticParams() {
  return specSource.generateParams();
}
