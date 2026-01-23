import { rfcsSource } from '@/lib/source';
import { DocsLayout } from 'fumadocs-ui/layouts/docs';
import { baseOptions } from '@/lib/layout.shared';
import Link from 'next/link';

function SidebarBanner() {
  return (
    <div className="relative px-3 pb-5 mb-4">
      <Link href="/" className="group flex items-center gap-3">
        <div className="relative">
          <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-amber-500 to-orange-600 flex items-center justify-center shadow-lg shadow-amber-500/25">
            <span className="text-white font-serif font-semibold text-sm">◈</span>
          </div>
          <div className="absolute -inset-1 bg-gradient-to-br from-amber-500 to-orange-600 rounded-xl opacity-0 group-hover:opacity-20 blur transition-opacity" />
        </div>
        <div className="flex flex-col">
          <span className="font-serif text-base font-medium text-foreground group-hover:text-amber-500 transition-colors">
            ferrule
          </span>
          <span className="text-[10px] uppercase tracking-widest text-muted-foreground">
            rfcs
          </span>
        </div>
      </Link>
      <div className="absolute bottom-0 left-3 right-3 h-px bg-gradient-to-r from-amber-500/30 via-border to-transparent" />
    </div>
  );
}

function SidebarFooter() {
  return (
    <div className="px-3 pt-4 mt-4 border-t border-border/30">
      <Link 
        href="/spec" 
        className="flex items-center gap-2 px-3 py-2 rounded-lg text-sm text-muted-foreground hover:text-foreground hover:bg-muted/50 transition-colors"
      >
        <span className="text-primary">◇</span>
        <span>View Spec</span>
        <span className="ml-auto text-xs text-muted-foreground/60">→</span>
      </Link>
      <Link 
        href="/plain/rfcs" 
        className="flex items-center gap-2 px-3 py-2 rounded-lg text-sm text-muted-foreground hover:text-foreground hover:bg-muted/50 transition-colors"
      >
        <span className="text-muted-foreground">◻</span>
        <span>Plain HTML</span>
        <span className="ml-auto text-xs text-muted-foreground/60">→</span>
      </Link>
    </div>
  );
}

export default function Layout({ children }: { children: React.ReactNode }) {
  return (
    <DocsLayout
      tree={rfcsSource.getPageTree()}
      {...baseOptions()}
      sidebar={{
        collapsible: true,
        defaultOpenLevel: 2,
        banner: <SidebarBanner />,
        footer: <SidebarFooter />,
      }}
    >
      {children}
    </DocsLayout>
  );
}
