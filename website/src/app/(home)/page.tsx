import Link from 'next/link';
import { ThemeBackground } from '@/components/theme-background';
import { tv } from 'tailwind-variants';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { LockSimpleIcon, WarningDiamondIcon, LightningIcon, ShieldCheckIcon } from '@phosphor-icons/react/dist/ssr';
import { Icon } from '@phosphor-icons/react';

const page = tv({
  slots: {
    wrapper: 'relative flex flex-col min-h-screen overflow-hidden',
    shaderBg: 'absolute inset-0 -z-20 animate-fade-in',
    gradientOverlay: 'absolute inset-0 -z-10 bg-gradient-to-b from-background/90 via-background/60 to-background',
    radialOverlay: 'absolute inset-0 -z-10 bg-[radial-gradient(ellipse_at_center,transparent_0%,var(--background)_60%)]',
    header: 'relative z-20 flex items-center justify-between px-4 py-4 sm:px-8 sm:py-6 animate-fade-in',
    headerLogo: 'text-sm font-medium tracking-wide text-foreground',
    nav: 'flex items-center gap-3 sm:gap-6',
    navLink: 'text-xs sm:text-sm text-muted-foreground hover:text-foreground transition-colors',
    main: 'relative z-10 flex-1 flex flex-col items-center justify-center px-4 sm:px-6 pb-16 sm:pb-24',
    heroSection: 'max-w-4xl mx-auto text-center w-full',
    heroBackdrop: 'relative px-4 py-8 sm:px-8 sm:py-12 rounded-2xl bg-background/40 backdrop-blur-md border border-border/20 animate-reveal',
    title: 'text-5xl sm:text-7xl lg:text-9xl font-serif font-medium tracking-tight mb-4 sm:mb-6 drop-shadow-lg',
    titleGradient: 'bg-gradient-to-r from-foreground via-foreground to-primary bg-clip-text text-transparent',
    tagline: 'text-lg sm:text-xl lg:text-2xl text-foreground/80 max-w-2xl mx-auto mb-3 sm:mb-4 leading-relaxed px-2',
    taglineHighlight: 'text-primary font-medium',
    subtitle: 'text-xs sm:text-sm lg:text-base text-muted-foreground max-w-lg mx-auto mb-8 sm:mb-10 px-2',
    buttonGroup: 'flex flex-col sm:flex-row gap-3 sm:gap-4 justify-center w-full sm:w-auto px-4 sm:px-0',
    codePreviewWrapper: 'mt-12 sm:mt-24 w-full max-w-5xl mx-auto animate-slide-up delay-300',
    codePreviewGlow: 'absolute -inset-1 bg-gradient-to-r from-primary/20 via-purple-500/20 to-pink-500/20 rounded-xl blur-xl opacity-50',
    codePreviewContainer: 'relative bg-card/80 backdrop-blur-md border border-border/50 rounded-xl overflow-hidden',
    codePreviewHeader: 'flex items-center gap-2 px-3 sm:px-4 py-2 sm:py-3 border-b border-border/50 bg-muted/30',
    codePreviewDot: 'w-2 h-2 sm:w-3 sm:h-3 rounded-full',
    codePreviewFilename: 'ml-3 sm:ml-4 text-xs text-muted-foreground font-mono',
    codePreviewBody: 'p-4 sm:p-6 text-xs sm:text-sm font-mono leading-relaxed overflow-x-auto',
    featuresGrid: 'mt-16 sm:mt-32 w-full max-w-4xl mx-auto grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-px bg-border/30 rounded-xl overflow-hidden animate-slide-up delay-400',
    notSection: 'mt-16 sm:mt-32 text-center px-4 animate-fade-in delay-500',
    notSectionTitle: 'text-xs text-muted-foreground/50 tracking-widest uppercase mb-3 sm:mb-2',
    notSectionItems: 'flex flex-col sm:flex-row flex-wrap justify-center gap-2 sm:gap-4 text-xs sm:text-sm text-muted-foreground',
    notSectionItem: 'px-3 py-1.5 sm:py-1 rounded-full bg-muted/30 border border-border/30',
    footer: 'relative z-10 px-4 sm:px-8 py-4 sm:py-6 text-center animate-fade-in delay-600',
    footerText: 'text-xs text-muted-foreground/40',
  },
});

const featureCard = tv({
  slots: {
    base: 'group relative p-4 sm:p-6 bg-card/60 backdrop-blur-sm hover:bg-card/80 transition-all duration-300',
    hoverOverlay: 'absolute inset-0 bg-gradient-to-br from-primary/5 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300',
    content: 'relative',
    icon: 'text-xl sm:text-2xl text-primary/60 group-hover:text-primary transition-colors duration-300 mb-3 sm:mb-4 block',
    title: 'text-sm font-medium mb-1.5 sm:mb-2 text-foreground',
    description: 'text-xs text-muted-foreground leading-relaxed',
  },
});

const styles = page();
const featureStyles = featureCard();

const c = {
  comment: 'text-muted-foreground',
  keyword: 'text-primary',
  fn: 'text-foreground',
  param: 'text-purple-400',
  type: 'text-pink-400',
  punct: 'text-muted-foreground',
  string: 'text-green-400',
};

export default function HomePage() {
  return (
    <div className={styles.wrapper()}>
      <ThemeBackground className={styles.shaderBg()} />

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
            <div className="mb-4 sm:mb-6">
              <Badge variant="outline" className="px-3 py-1 text-xs font-medium tracking-wide text-primary border-primary/40 bg-primary/10">
                α1 preview
              </Badge>
            </div>

            <h1 className={styles.title()}>
              <span className={styles.titleGradient()}>
                ferrule
              </span>
            </h1>

            <p className={styles.tagline()}>
              a systems language where{' '}
              <span className={styles.taglineHighlight()}>effects</span> and{' '}
              <span className={styles.taglineHighlight()}>capabilities</span> are first-class
            </p>

            <p className={styles.subtitle()}>
              low-level control with safety guarantees about what code can do,
              not just what memory it touches
            </p>

            <div className={styles.buttonGroup()}>
              <Link href="/spec" className="w-full sm:w-auto">
                <Button size="lg" className="w-full sm:w-auto px-8 cursor-pointer">
                  read the spec
                </Button>
              </Link>
              <Link href="/rfcs" className="w-full sm:w-auto">
                <Button variant="outline" size="lg" className="w-full sm:w-auto px-8 cursor-pointer bg-background/50 backdrop-blur-sm border-border/50">
                  browse rfcs
                </Button>
              </Link>
            </div>
          </div>
        </div>

        <div className={styles.codePreviewWrapper()}>
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
                  <span className={c.comment}>{'// explicit capabilities, no ambient authority'}</span>
                  {'\n'}
                  <span className={c.keyword}>function</span>
                  {' '}
                  <span className={c.fn}>main</span>
                  <span className={c.punct}>(</span>
                  <span className={c.keyword}>cap</span>
                  {' '}
                  <span className={c.param}>io</span>
                  <span className={c.punct}>{': '}</span>
                  <span className={c.type}>IO</span>
                  <span className={c.punct}>{')'}</span>
                  {' '}
                  <span className={c.keyword}>effects</span>
                  {' '}
                  <span className={c.punct}>{'['}</span>
                  <span className={c.type}>io</span>
                  <span className={c.punct}>{'] {'}</span>
                  {'\n'}
                  {'  '}
                  <span className={c.fn}>io</span>
                  <span className={c.punct}>.</span>
                  <span className={c.fn}>println</span>
                  <span className={c.punct}>(</span>
                  <span className={c.string}>{'"hello, world"'}</span>
                  <span className={c.punct}>);</span>
                  {'\n'}
                  <span className={c.punct}>{'}'}</span>
                </code>
              </pre>
            </div>
          </div>
        </div>

        <div className={styles.featuresGrid()}>
          <FeatureCard
            icon={LockSimpleIcon}
            title="immutability first"
            description="const by default, var when you need mutation, inout for explicit by-reference"
          />
          <FeatureCard
            icon={WarningDiamondIcon}
            title="errors as values"
            description="no exceptions, typed error domains, lightweight propagation with check"
          />
          <FeatureCard
            icon={LightningIcon}
            title="explicit effects"
            description="functions declare what they do, async is just another effect"
          />
          <FeatureCard
            icon={ShieldCheckIcon}
            title="capability security"
            description="no ambient authority, fs/net/clock are values you pass"
          />
        </div>

        <div className={styles.notSection()}>
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
  icon: IconComponent,
  title,
  description,
}: {
  icon: Icon;
  title: string;
  description: string;
}) {
  return (
    <div className={featureStyles.base()}>
      <div className={featureStyles.hoverOverlay()} />
      <div className={featureStyles.content()}>
        <IconComponent weight="duotone" className={featureStyles.icon()} />
        <h3 className={featureStyles.title()}>{title}</h3>
        <p className={featureStyles.description()}>{description}</p>
      </div>
    </div>
  );
}
