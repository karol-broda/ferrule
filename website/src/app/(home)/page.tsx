'use client';

import Link from 'next/link';
import { Dithering } from '@paper-design/shaders-react';
import { tv } from 'tailwind-variants';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { useTheme } from 'next-themes';
import { useSyncExternalStore } from 'react';

const page = tv({
  slots: {
    wrapper: 'relative flex flex-col min-h-screen overflow-hidden',
    shaderBg: 'absolute inset-0 -z-20',
    gradientOverlay: 'absolute inset-0 -z-10 bg-gradient-to-b from-background/90 via-background/60 to-background',
    radialOverlay: 'absolute inset-0 -z-10 bg-[radial-gradient(ellipse_at_center,transparent_0%,var(--background)_60%)]',
    header: 'relative z-20 flex items-center justify-between px-8 py-6',
    headerLogo: 'text-sm font-medium tracking-wide text-foreground',
    nav: 'flex items-center gap-6',
    navLink: 'text-sm text-muted-foreground hover:text-foreground transition-colors',
    main: 'relative z-10 flex-1 flex flex-col items-center justify-center px-6 pb-24',
    heroSection: 'max-w-4xl mx-auto text-center',
    heroBackdrop: 'relative px-8 py-12 rounded-2xl bg-background/40 backdrop-blur-md border border-border/20',
    title: 'text-6xl sm:text-8xl lg:text-9xl font-serif font-medium tracking-tight mb-6 drop-shadow-lg',
    titleGradient: 'bg-gradient-to-r from-foreground via-foreground to-primary bg-clip-text text-transparent',
    tagline: 'text-xl sm:text-2xl text-foreground/80 max-w-2xl mx-auto mb-4 leading-relaxed',
    taglineHighlight: 'text-primary font-medium',
    subtitle: 'text-sm sm:text-base text-muted-foreground max-w-lg mx-auto mb-10',
    buttonGroup: 'flex flex-wrap gap-4 justify-center',
    codePreviewWrapper: 'mt-24 w-full max-w-5xl mx-auto',
    codePreviewGlow: 'absolute -inset-1 bg-gradient-to-r from-primary/20 via-purple-500/20 to-pink-500/20 rounded-xl blur-xl opacity-50',
    codePreviewContainer: 'relative bg-card/80 backdrop-blur-md border border-border/50 rounded-xl overflow-hidden',
    codePreviewHeader: 'flex items-center gap-2 px-4 py-3 border-b border-border/50 bg-muted/30',
    codePreviewDot: 'w-3 h-3 rounded-full',
    codePreviewFilename: 'ml-4 text-xs text-muted-foreground font-mono',
    codePreviewBody: 'p-6 text-sm font-mono leading-relaxed overflow-x-auto',
    featuresGrid: 'mt-32 w-full max-w-4xl mx-auto grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-px bg-border/30 rounded-xl overflow-hidden',
    notSection: 'mt-32 text-center',
    notSectionTitle: 'text-xs text-muted-foreground/50 tracking-widest uppercase mb-2',
    notSectionItems: 'flex flex-wrap justify-center gap-4 text-sm text-muted-foreground',
    notSectionItem: 'px-3 py-1 rounded-full bg-muted/30 border border-border/30',
    footer: 'relative z-10 px-8 py-6 text-center',
    footerText: 'text-xs text-muted-foreground/40',
  },
});

const featureCard = tv({
  slots: {
    base: 'group relative p-6 bg-card/60 backdrop-blur-sm hover:bg-card/80 transition-all duration-300',
    hoverOverlay: 'absolute inset-0 bg-gradient-to-br from-primary/5 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300',
    content: 'relative',
    icon: 'text-2xl text-primary/60 group-hover:text-primary transition-colors duration-300 mb-4 block',
    title: 'text-sm font-medium mb-2 text-foreground',
    description: 'text-xs text-muted-foreground leading-relaxed',
  },
});

const animation = tv({
  base: 'animate-fade-in',
  variants: {
    delay: {
      0: '',
      100: 'animation-delay-100',
      200: 'animation-delay-200',
      300: 'animation-delay-300',
      400: 'animation-delay-400',
      500: 'animation-delay-500',
      600: 'animation-delay-600',
      700: 'animation-delay-700',
      800: 'animation-delay-800',
      900: 'animation-delay-900',
      1000: 'animation-delay-1000',
    },
  },
  defaultVariants: {
    delay: 0,
  },
});

const emptySubscribe = () => () => {};

export default function HomePage() {
  const styles = page();
  const { resolvedTheme } = useTheme();
  const mounted = useSyncExternalStore(emptySubscribe, () => true, () => false);

  const isDark = mounted ? resolvedTheme === 'dark' : true;
  
  return (
    <div className={styles.wrapper()}>
      <div className={styles.shaderBg()}>
        <Dithering
          colorBack={isDark ? '#0d0614' : '#f5f0fa'}
          colorFront={isDark ? '#a855f7' : '#9333ea'}
          shape="simplex"
          type="4x4"
          size={2}
          speed={0.15}
          scale={1.2}
          style={{ width: '100%', height: '100%' }}
        />
      </div>

      <div className={styles.gradientOverlay()} />
      <div className={styles.radialOverlay()} />

      <header className={styles.header()}>
        <span className={styles.headerLogo()}>ferrule</span>
        <nav className={styles.nav()}>
          <Link href="/spec" className={styles.navLink()}>
            spec
          </Link>
          <Link href="/rfcs" className={styles.navLink()}>
            rfcs
          </Link>
          <a
            href="https://github.com/ferrule-lang/ferrule"
            target="_blank"
            rel="noopener noreferrer"
            className={styles.navLink()}
          >
            github
          </a>
        </nav>
      </header>

      <main className={styles.main()}>
        <div className={styles.heroSection()}>
          <div className={styles.heroBackdrop()}>
            <div className={animation({ delay: 0, className: 'mb-6' })}>
              <Badge variant="outline" className="px-3 py-1 text-xs font-medium tracking-widest uppercase text-primary border-primary/40 bg-primary/10">
                α1 preview
              </Badge>
            </div>

            <h1 className={animation({ delay: 100, className: styles.title() })}>
              <span className={styles.titleGradient()}>
                ferrule
              </span>
            </h1>

            <p className={animation({ delay: 200, className: styles.tagline() })}>
              a systems language where{' '}
              <span className={styles.taglineHighlight()}>effects</span> and{' '}
              <span className={styles.taglineHighlight()}>capabilities</span> are first-class
            </p>

            <p className={animation({ delay: 300, className: styles.subtitle() })}>
              low-level control with safety guarantees about what code can do,
              not just what memory it touches
            </p>

            <div className={animation({ delay: 400, className: styles.buttonGroup() })}>
              <Link href="/spec">
                <Button size="lg" className="px-8">
                  read the spec
                </Button>
              </Link>
              <Link href="/rfcs">
                <Button variant="outline" size="lg" className="px-8 bg-background/50 backdrop-blur-sm border-border/50">
                  browse rfcs
                </Button>
              </Link>
            </div>
          </div>
        </div>

        <div className={animation({ delay: 500, className: styles.codePreviewWrapper() })}>
          <div className="relative">
            <div className={styles.codePreviewGlow()} />
            <div className={styles.codePreviewContainer()}>
              <div className={styles.codePreviewHeader()}>
                <div className={`${styles.codePreviewDot()} bg-red-500/60`} />
                <div className={`${styles.codePreviewDot()} bg-yellow-500/60`} />
                <div className={`${styles.codePreviewDot()} bg-green-500/60`} />
                <span className={styles.codePreviewFilename()}>hello.fe</span>
              </div>
              <pre className={styles.codePreviewBody()}>
                <code>
                  <span className="text-muted-foreground">{'// explicit capabilities, no ambient authority'}</span>{'\n'}
                  <span className="text-primary">function</span>{' '}
                  <span className="text-foreground">main</span>
                  <span className="text-muted-foreground">(</span>
                  <span className="text-purple-400">io</span>
                  <span className="text-muted-foreground">:</span>{' '}
                  <span className="text-pink-400">cap IO</span>
                  <span className="text-muted-foreground">)</span>{' '}
                  <span className="text-muted-foreground">{'{'}</span>{'\n'}
                  {'  '}<span className="text-foreground">io</span>
                  <span className="text-muted-foreground">.</span>
                  <span className="text-foreground">println</span>
                  <span className="text-muted-foreground">(</span>
                  <span className="text-green-400">{'"hello, world"'}</span>
                  <span className="text-muted-foreground">)</span>
                  <span className="text-muted-foreground">;</span>{'\n'}
                  <span className="text-muted-foreground">{'}'}</span>
                </code>
              </pre>
            </div>
          </div>
        </div>

        <div className={styles.featuresGrid()}>
          <FeatureCard
            icon="◇"
            title="immutability first"
            description="const by default, var when you need mutation, inout for explicit by-reference"
            delay={600}
          />
          <FeatureCard
            icon="◈"
            title="errors as values"
            description="no exceptions, typed error domains, lightweight propagation with check"
            delay={700}
          />
          <FeatureCard
            icon="◊"
            title="explicit effects"
            description="functions declare what they do, async is just another effect"
            delay={800}
          />
          <FeatureCard
            icon="⬡"
            title="capability security"
            description="no ambient authority, fs/net/clock are values you pass"
            delay={900}
          />
        </div>

        <div className={animation({ delay: 1000, className: styles.notSection() })}>
          <p className={styles.notSectionTitle()}>
            {"what it's not"}
          </p>
          <div className={styles.notSectionItems()}>
            <span className={styles.notSectionItem()}>not rust · no borrow checker</span>
            <span className={styles.notSectionItem()}>not zig · effects are language features</span>
            <span className={styles.notSectionItem()}>not go · no gc, explicit errors</span>
          </div>
        </div>
      </main>

      <footer className={styles.footer()}>
        <p className={styles.footerText()}>
          ferrule © 2026 — specification draft
        </p>
      </footer>
    </div>
  );
}

function FeatureCard({
  icon,
  title,
  description,
  delay,
}: {
  icon: string;
  title: string;
  description: string;
  delay: 600 | 700 | 800 | 900;
}) {
  const styles = featureCard();
  
  return (
    <div className={animation({ delay, className: styles.base() })}>
      <div className={styles.hoverOverlay()} />
      <div className={styles.content()}>
        <span className={styles.icon()}>{icon}</span>
        <h3 className={styles.title()}>{title}</h3>
        <p className={styles.description()}>{description}</p>
      </div>
    </div>
  );
}
