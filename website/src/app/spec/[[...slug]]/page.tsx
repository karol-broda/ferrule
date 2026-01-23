import { specSource } from '@/lib/source';
import { DocsBody, DocsPage } from 'fumadocs-ui/layouts/docs/page';
import { notFound } from 'next/navigation';
import { getMDXComponents } from '@/mdx-components';
import type { Metadata } from 'next';
import { createRelativeLink } from 'fumadocs-ui/mdx';
import { Badge } from '@/components/ui/badge';
import { tv } from 'tailwind-variants';

const styles = tv({
  slots: {
    header: 'relative mb-8 pb-8 border-b border-border/50',
    headerDecor: 'absolute -left-4 top-0 bottom-0 w-1 bg-gradient-to-b from-primary via-purple-500 to-transparent rounded-full',
    titleRow: 'flex items-start gap-4 flex-wrap',
    title: 'font-serif text-3xl sm:text-4xl font-medium tracking-tight text-foreground',
    description: 'mt-3 text-base text-muted-foreground leading-relaxed max-w-2xl',
    metaRow: 'mt-4 flex flex-wrap items-center gap-2',
    statusBadge: 'text-xs font-medium',
    implBadge: 'text-[10px] font-medium px-1.5 py-0.5',
  },
});

const statusVariants = tv({
  base: 'text-xs font-medium',
  variants: {
    status: {
      'α1': 'bg-primary/15 text-primary border-primary/30',
      'α2': 'bg-purple-500/15 text-purple-500 border-purple-500/30',
      'β': 'bg-muted text-muted-foreground border-border',
      'rfc': 'bg-amber-500/15 text-amber-600 border-amber-500/30',
      'draft': 'bg-muted text-muted-foreground border-border',
    },
  },
  defaultVariants: {
    status: 'draft',
  },
});

const implVariants = tv({
  base: 'text-[10px] font-medium px-1.5 py-0.5',
  variants: {
    type: {
      implemented: 'bg-green-500/15 text-green-600 border-green-500/30',
      pending: 'bg-amber-500/15 text-amber-600 border-amber-500/30',
      deferred: 'bg-muted text-muted-foreground border-border',
    },
  },
});

function StatusBadge({ status }: { status: string }) {
  const validStatus = ['α1', 'α2', 'β', 'rfc', 'draft'].includes(status) 
    ? status as 'α1' | 'α2' | 'β' | 'rfc' | 'draft'
    : 'draft';
  
  return (
    <Badge variant="outline" className={statusVariants({ status: validStatus })}>
      {status}
    </Badge>
  );
}

function ImplementationBadges({ 
  implemented, 
  pending, 
  deferred 
}: { 
  implemented?: string[]; 
  pending?: string[]; 
  deferred?: string[]; 
}) {
  const hasAny = (implemented !== undefined && implemented.length > 0) || 
                 (pending !== undefined && pending.length > 0) || 
                 (deferred !== undefined && deferred.length > 0);
  
  if (!hasAny) return null;

  return (
    <>
      {implemented !== undefined && implemented.map((item) => (
        <Badge key={item} variant="outline" className={implVariants({ type: 'implemented' })}>
          ✓ {item}
        </Badge>
      ))}
      {pending !== undefined && pending.map((item) => (
        <Badge key={item} variant="outline" className={implVariants({ type: 'pending' })}>
          ○ {item}
        </Badge>
      ))}
      {deferred !== undefined && deferred.map((item) => (
        <Badge key={item} variant="outline" className={implVariants({ type: 'deferred' })}>
          ◌ {item}
        </Badge>
      ))}
    </>
  );
}

export default async function Page(props: { params: Promise<{ slug?: string[] }> }) {
  const params = await props.params;
  const page = specSource.getPage(params.slug);
  if (page === null || page === undefined) notFound();

  const MDX = page.data.body;
  const s = styles();

  return (
    <DocsPage toc={page.data.toc} full={page.data.full}>
      <header className={s.header()}>
        <div className={s.headerDecor()} />
        <div className={s.titleRow()}>
          <h1 className={s.title()}>{page.data.title}</h1>
          {page.data.status !== null && page.data.status !== undefined && (
            <StatusBadge status={page.data.status} />
          )}
        </div>
        {page.data.description !== null && page.data.description !== undefined && (
          <p className={s.description()}>{page.data.description}</p>
        )}
        <div className={s.metaRow()}>
          <ImplementationBadges 
            implemented={page.data.implemented}
            pending={page.data.pending}
            deferred={page.data.deferred}
          />
        </div>
      </header>
      <DocsBody>
        <MDX
          components={getMDXComponents({
            a: createRelativeLink(specSource, page),
          })}
        />
      </DocsBody>
    </DocsPage>
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
    title: page.data.title,
    description: page.data.description,
  };
}
