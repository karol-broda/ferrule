'use client';

import Link from 'next/link';
import { Dithering } from '@/components/dithering';
import { Button } from '@/components/ui/button';
import { useTheme } from 'next-themes';
import { useSyncExternalStore } from 'react';

const emptySubscribe = () => () => {};

export default function NotFound() {
  const { resolvedTheme } = useTheme();
  const mounted = useSyncExternalStore(emptySubscribe, () => true, () => false);
  const isDark = mounted ? resolvedTheme === 'dark' : true;

  return (
    <div className="relative flex flex-col min-h-screen overflow-hidden">
      <div className="absolute inset-0 -z-20">
        <Dithering
          colorBack={isDark ? '#0d0614' : '#f5f0fa'}
          colorFront={isDark ? '#a855f7' : '#9333ea'}
          type="4x4"
          size={3}
          speed={0.08}
          scale={1.5}
          style={{ width: '100%', height: '100%' }}
        />
      </div>

      <div className="absolute inset-0 -z-10 bg-linear-to-b from-background/70 via-background/40 to-background/70" />
      <div className="absolute inset-0 -z-10 bg-[radial-gradient(ellipse_at_center,var(--background)_0%,transparent_60%)]" />

      <header className="flex items-center justify-between px-4 py-4 sm:px-8 sm:py-6">
        <Link href="/" className="text-sm font-medium tracking-wide text-foreground hover:text-primary transition-colors">
          ferrule
        </Link>
      </header>

      <main className="flex-1 flex flex-col items-center justify-center px-4">
        <div className="text-center space-y-6">
          <div className="relative inline-block">
            <div className="absolute -inset-8 bg-[radial-gradient(ellipse_at_center,var(--background)_0%,transparent_70%)]" />
            
            <div className="relative">
              <h1 className="text-7xl sm:text-9xl font-serif font-medium mb-4">
                <span className="bg-linear-to-r from-foreground via-foreground to-primary bg-clip-text text-transparent">
                  404
                </span>
              </h1>

              <p className="text-lg sm:text-xl text-foreground/80 mb-1">
                page not found
              </p>

              <p className="text-sm text-muted-foreground font-mono mb-8">
                {"// this capability was not granted"}
              </p>

              <Link href="/">
                <Button size="lg" className="px-10 cursor-pointer">
                  ← back home
                </Button>
              </Link>
            </div>
          </div>
        </div>
      </main>

      <footer className="px-4 py-6 text-center">
        <div className="flex items-center justify-center gap-4 text-muted-foreground/30 text-sm">
          <span>◇</span>
          <span>◈</span>
          <span>◊</span>
          <span>⬡</span>
        </div>
      </footer>
    </div>
  );
}
