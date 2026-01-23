import { rfcsSource } from '@/lib/source';
import { DocsBody, DocsPage } from 'fumadocs-ui/layouts/docs/page';
import { notFound } from 'next/navigation';
import { getMDXComponents } from '@/mdx-components';
import type { Metadata } from 'next';
import { createRelativeLink } from 'fumadocs-ui/mdx';
import { Badge } from '@/components/ui/badge';
import { tv } from 'tailwind-variants';
import Link from 'next/link';

const styles = tv({
  slots: {
    header: 'relative mb-8 pb-8 border-b border-border/50',
    headerDecor: 'absolute -left-4 top-0 bottom-0 w-1 bg-gradient-to-b from-amber-500 via-orange-500 to-transparent rounded-full',
    titleRow: 'flex items-start gap-4 flex-wrap',
    title: 'font-serif text-3xl sm:text-4xl font-medium tracking-tight text-foreground',
    description: 'mt-3 text-base text-muted-foreground leading-relaxed max-w-2xl',
    metaRow: 'mt-4 flex flex-wrap items-center gap-2',
    rfcNumber: 'font-mono text-sm text-amber-600',
  },
});

const statusVariants = tv({
  base: 'text-xs font-medium',
  variants: {
    status: {
      draft: 'bg-muted text-muted-foreground border-border',
      accepted: 'bg-green-500/15 text-green-600 border-green-500/30',
      implemented: 'bg-primary/15 text-primary border-primary/30',
      rejected: 'bg-red-500/15 text-red-600 border-red-500/30',
      deferred: 'bg-muted text-muted-foreground border-border',
    },
  },
  defaultVariants: {
    status: 'draft',
  },
});

const targetVariants = tv({
  base: 'text-xs font-medium',
  variants: {
    target: {
      'α1': 'bg-primary/15 text-primary border-primary/30',
      'α2': 'bg-purple-500/15 text-purple-500 border-purple-500/30',
      'β': 'bg-muted text-muted-foreground border-border',
    },
  },
  defaultVariants: {
    target: 'β',
  },
});

function StatusBadge({ status }: { status: string }) {
  const validStatus = ['draft', 'accepted', 'implemented', 'rejected', 'deferred'].includes(status) 
    ? status as 'draft' | 'accepted' | 'implemented' | 'rejected' | 'deferred'
    : 'draft';
  
  return (
    <Badge variant="outline" className={statusVariants({ status: validStatus })}>
      {status}
    </Badge>
  );
}

function TargetBadge({ target }: { target: string }) {
  const validTarget = ['α1', 'α2', 'β'].includes(target) 
    ? target as 'α1' | 'α2' | 'β'
    : 'β';
  
  return (
    <Badge variant="outline" className={targetVariants({ target: validTarget })}>
      target: {target}
    </Badge>
  );
}

function DependsBadges({ depends }: { depends?: Array<string | number> }) {
  if (depends === null || depends === undefined || depends.length === 0) return null;
  
  return (
    <>
      {depends.map((dep) => (
        <Link key={dep} href={`/rfcs/${String(dep).padStart(4, '0')}`}>
          <Badge 
            variant="outline" 
            className="text-[10px] font-medium px-1.5 py-0.5 bg-muted/50 hover:bg-muted transition-colors cursor-pointer"
          >
            depends: RFC-{String(dep).padStart(4, '0')}
          </Badge>
        </Link>
      ))}
    </>
  );
}

export default async function Page(props: { params: Promise<{ slug?: string[] }> }) {
  const params = await props.params;
  const page = rfcsSource.getPage(params.slug);
  if (page === null || page === undefined) notFound();

  const MDX = page.data.body;
  const s = styles();

  const rfcNumber = page.data.rfc !== null && page.data.rfc !== undefined 
    ? `RFC-${String(page.data.rfc).padStart(4, '0')}`
    : null;

  return (
    <DocsPage toc={page.data.toc} full={page.data.full}>
      <header className={s.header()}>
        <div className={s.headerDecor()} />
        {rfcNumber !== null && (
          <span className={s.rfcNumber()}>{rfcNumber}</span>
        )}
        <div className={s.titleRow()}>
          <h1 className={s.title()}>{page.data.title}</h1>
        </div>
        {page.data.description !== null && page.data.description !== undefined && (
          <p className={s.description()}>{page.data.description}</p>
        )}
        <div className={s.metaRow()}>
          {page.data.status !== null && page.data.status !== undefined && (
            <StatusBadge status={page.data.status} />
          )}
          {page.data.target !== null && page.data.target !== undefined && (
            <TargetBadge target={page.data.target} />
          )}
          <DependsBadges depends={page.data.depends} />
        </div>
      </header>
      <DocsBody>
        <MDX
          components={getMDXComponents({
            a: createRelativeLink(rfcsSource, page),
          })}
        />
      </DocsBody>
    </DocsPage>
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
    title: `${rfcPrefix}${page.data.title}`,
    description: page.data.description,
  };
}
