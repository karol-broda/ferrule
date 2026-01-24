'use client';

import { useTheme } from 'next-themes';
import { useSyncExternalStore } from 'react';
import { Dithering } from '@/components/dithering';

const emptySubscribe = () => () => {};

export function ThemeBackground({ className }: { className?: string }) {
  const { resolvedTheme } = useTheme();
  const mounted = useSyncExternalStore(emptySubscribe, () => true, () => false);

  const isDark = mounted ? resolvedTheme === 'dark' : true;

  return (
    <div className={className}>
      <Dithering
        colorBack={isDark ? '#0d0614' : '#f5f0fa'}
        colorFront={isDark ? '#a855f7' : '#9333ea'}
        type="4x4"
        size={2}
        speed={0.15}
        scale={1.2}
        style={{ width: '100%', height: '100%' }}
      />
    </div>
  );
}
