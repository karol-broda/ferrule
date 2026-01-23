import { rfcsSource } from '@/lib/source';
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
      <Link href="/plain/rfcs">rfcs</Link>
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
  const pages = rfcsSource.getPages();
  
  const rfcList = pages.map((page) => {
    const rfcNumber = page.data.rfc !== null && page.data.rfc !== undefined
      ? String(page.data.rfc).padStart(4, '0')
      : null;
    
    return {
      url: `/plain${page.url}`,
      title: page.data.title,
      description: page.data.description,
      rfcNumber,
      status: page.data.status,
      target: page.data.target,
    };
  }).sort((a, b) => {
    if (a.rfcNumber !== null && b.rfcNumber !== null) {
      return a.rfcNumber.localeCompare(b.rfcNumber);
    }
    if (a.rfcNumber !== null) return -1;
    if (b.rfcNumber !== null) return 1;
    return a.title.localeCompare(b.title);
  });

  return (
    <>
      <h2>all rfcs</h2>
      <table>
        <thead>
          <tr>
            <th>rfc</th>
            <th>title</th>
            <th>status</th>
            <th>target</th>
          </tr>
        </thead>
        <tbody>
          {rfcList.map((rfc) => (
            <tr key={rfc.url}>
              <td>
                {rfc.rfcNumber !== null ? (
                  <code>RFC-{rfc.rfcNumber}</code>
                ) : (
                  <em>-</em>
                )}
              </td>
              <td>
                <Link href={rfc.url}>{rfc.title}</Link>
              </td>
              <td>{rfc.status !== null && rfc.status !== undefined ? rfc.status : '-'}</td>
              <td>{rfc.target !== null && rfc.target !== undefined ? rfc.target : '-'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </>
  );
}

export default async function Page(props: { params: Promise<{ slug?: string[] }> }) {
  const params = await props.params;
  const page = rfcsSource.getPage(params.slug);
  if (page === null || page === undefined) notFound();

  const MDX = page.data.body;
  const slugs = params.slug !== undefined && params.slug !== null ? params.slug : [];
  const isIndex = slugs.length === 0;

  const rfcNumber = page.data.rfc !== null && page.data.rfc !== undefined 
    ? `RFC-${String(page.data.rfc).padStart(4, '0')}`
    : null;

  return (
    <main>
      <Breadcrumb slugs={slugs} />
      
      {rfcNumber !== null && (
        <p><code>{rfcNumber}</code></p>
      )}
      
      <h1>{page.data.title}</h1>
      
      {page.data.description !== null && page.data.description !== undefined && (
        <p className="meta">
          <em>{page.data.description}</em>
        </p>
      )}
      
      {(page.data.status !== null && page.data.status !== undefined) || (page.data.target !== null && page.data.target !== undefined) ? (
        <p className="meta">
          {page.data.status !== null && page.data.status !== undefined && (
            <>Status: <strong>{page.data.status}</strong></>
          )}
          {page.data.target !== null && page.data.target !== undefined && (
            <>{page.data.status !== null && page.data.status !== undefined ? ' | ' : ''}Target: <strong>{page.data.target}</strong></>
          )}
        </p>
      ) : null}

      <hr />

      <MDX components={getPlainMDXComponents()} />

      {isIndex && <PageIndex />}
    </main>
  );
}

export async function generateStaticParams() {
  return rfcsSource.generateParams();
}

export async function generateMetadata(props: { params: Promise<{ slug?: string[] }> }): Promise<Metadata> {
  const params = await props.params;
  const page = rfcsSource.getPage(params.slug);
  if (page === null || page === undefined) notFound();

  const rfcPrefix = page.data.rfc !== null && page.data.rfc !== undefined 
    ? `RFC-${String(page.data.rfc).padStart(4, '0')}: `
    : '';

  return {
    title: `${rfcPrefix}${page.data.title} (plain)`,
    description: page.data.description,
  };
}
