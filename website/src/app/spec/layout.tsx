import { specSource } from '@/lib/source';
import { DocsLayout } from 'fumadocs-ui/layouts/docs';
import { baseOptions } from '@/lib/layout.shared';
import Link from 'next/link';

function SidebarBanner() {
  return (
    <div className="relative px-3 pb-5 mb-4">
      <Link href="/" className="group flex items-center gap-3">
        <div className="relative">
          <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-primary to-purple-600 flex items-center justify-center shadow-lg shadow-primary/25">
            <span className="text-primary-foreground font-serif font-semibold text-sm">f</span>
          </div>
          <div className="absolute -inset-1 bg-gradient-to-br from-primary to-purple-600 rounded-xl opacity-0 group-hover:opacity-20 blur transition-opacity" />
        </div>
        <div className="flex flex-col">
          <span className="font-serif text-base font-medium text-foreground group-hover:text-primary transition-colors">
            ferrule
          </span>
          <span className="text-[10px] uppercase tracking-widest text-muted-foreground">
            specification
          </span>
        </div>
      </Link>
      <div className="absolute bottom-0 left-3 right-3 h-px bg-gradient-to-r from-primary/30 via-border to-transparent" />
    </div>
  );
}

function SidebarFooter() {
  return (
    <div className="px-3 pt-4 mt-4 border-t border-border/30">
      <Link 
        href="/rfcs" 
        className="flex items-center gap-2 px-3 py-2 rounded-lg text-sm text-muted-foreground hover:text-foreground hover:bg-muted/50 transition-colors"
      >
        <span className="text-amber-500">◈</span>
        <span>View RFCs</span>
        <span className="ml-auto text-xs text-muted-foreground/60">→</span>
      </Link>
    </div>
  );
}

export default function Layout({ children }: { children: React.ReactNode }) {
  return (
    <DocsLayout
      tree={specSource.getPageTree()}
      {...baseOptions()}
      sidebar={{
        collapsible: true,
        defaultOpenLevel: 1,
        banner: <SidebarBanner />,
        footer: <SidebarFooter />,
      }}
    >
      {children}
    </DocsLayout>
  );
}
