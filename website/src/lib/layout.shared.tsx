import type { BaseLayoutProps } from 'fumadocs-ui/layouts/shared';

export function baseOptions(): BaseLayoutProps {
  return {
    nav: {
      title: (
        <span className="font-semibold tracking-tight">
          ferrule
        </span>
      ),
    },
    links: [
      {
        text: 'Spec',
        url: '/spec',
        active: 'nested-url',
      },
      {
        text: 'RFCs',
        url: '/rfcs',
        active: 'nested-url',
      },
      {
        text: 'GitHub',
        url: 'https://github.com/ferrule-lang/ferrule',
        external: true,
      },
    ],
    githubUrl: 'https://github.com/ferrule-lang/ferrule',
  };
}
