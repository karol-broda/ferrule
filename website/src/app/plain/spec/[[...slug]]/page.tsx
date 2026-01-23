import { specSource } from '@/lib/source';
import { notFound } from 'next/navigation';
import { getPlainMDXComponents } from '@/lib/plain-mdx-components';
import type { Metadata } from 'next';
import Link from 'next/link';

function Breadcrumb({ slugs }: { slugs: string[] }) {
  if (slugs.length === 0) {
    return null;
  }

  return (
    <p className="breadcrumb">
      <Link href="/plain/spec">spec</Link>
      {slugs.map((slug, i) => (
        <span key={i}>
          {' > '}
          <span>{slug}</span>
        </span>
      ))}
    </p>
  );
}

function PageIndex() {
  const pages = specSource.getPages();
  
  const grouped: Record<string, Array<{ url: string; title: string; description?: string }>> = {};
  
  for (const page of pages) {
    const category = page.slugs.length > 1 ? page.slugs[0] : 'root';
    if (grouped[category] === undefined) {
      grouped[category] = [];
    }
    grouped[category].push({
      url: `/plain${page.url}`,
      title: page.data.title,
      description: page.data.description,
    });
  }

  const categoryOrder = ['root', 'core', 'functions', 'errors', 'memory', 'modules', 'unsafe', 'concurrency', 'advanced', 'reference'];
  const sortedCategories = Object.keys(grouped).sort((a, b) => {
    const aIndex = categoryOrder.indexOf(a);
    const bIndex = categoryOrder.indexOf(b);
    if (aIndex === -1 && bIndex === -1) return a.localeCompare(b);
    if (aIndex === -1) return 1;
    if (bIndex === -1) return -1;
    return aIndex - bIndex;
  });

  return (
    <>
      <h2>pages in this section</h2>
      {sortedCategories.map((category) => (
        <div key={category}>
          {category !== 'root' && <h3>{category}</h3>}
          <ul>
            {grouped[category].map((page) => (
              <li key={page.url}>
                <Link href={page.url}>{page.title}</Link>
                {page.description !== null && page.description !== undefined && (
                  <> - <em>{page.description}</em></>
                )}
              </li>
            ))}
          </ul>
        </div>
      ))}
    </>
  );
}

export default async function Page(props: { params: Promise<{ slug?: string[] }> }) {
  const params = await props.params;
  const page = specSource.getPage(params.slug);
  if (page === null || page === undefined) notFound();

  const MDX = page.data.body;
  const slugs = params.slug !== undefined && params.slug !== null ? params.slug : [];
  const isIndex = slugs.length === 0;

  return (
    <main>
      <Breadcrumb slugs={slugs} />
      
      <h1>{page.data.title}</h1>
      
      {page.data.description !== null && page.data.description !== undefined && (
        <p className="meta">
          <em>{page.data.description}</em>
        </p>
      )}
      
      {page.data.status !== null && page.data.status !== undefined && (
        <p className="meta">
          Status: <strong>{page.data.status}</strong>
        </p>
      )}

      <hr />

      <MDX components={getPlainMDXComponents()} />

      {isIndex && <PageIndex />}
    </main>
  );
}

export async function generateStaticParams() {
  return specSource.generateParams();
}

export async function generateMetadata(props: { params: Promise<{ slug?: string[] }> }): Promise<Metadata> {
  const params = await props.params;
  const page = specSource.getPage(params.slug);
  if (page === null || page === undefined) notFound();

  return {
    title: `${page.data.title} (plain)`,
    description: page.data.description,
  };
}
