import { createMDX } from 'fumadocs-mdx/next';

const withMDX = createMDX();

/** @type {import('next').NextConfig} */
const config = {
  reactStrictMode: true,
  output: 'standalone',
  turbopack: {
    root: '..',
  },
  async rewrites() {
    return [
      {
        source: '/spec/:path*.mdx',
        destination: '/llms.mdx/spec/:path*',
      },
      {
        source: '/rfcs/:path*.mdx',
        destination: '/llms.mdx/rfcs/:path*',
      },
    ];
  },
  async redirects() {
    return [
      {
        source: '/docs',
        destination: '/spec',
        permanent: true,
      },
      {
        source: '/docs/:path*',
        destination: '/spec/:path*',
        permanent: true,
      },
    ];
  },
};

export default withMDX(config);
