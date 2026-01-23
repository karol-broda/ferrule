import { specSource, rfcsSource } from '@/lib/source';
import { createSearchAPI } from 'fumadocs-core/search/server';

export const { GET } = createSearchAPI('advanced', {
  indexes: async () => {
    const specPages = specSource.getPages();
    const rfcsPages = rfcsSource.getPages();

    return [
      ...specPages.map((page) => ({
        id: page.url,
        title: page.data.title,
        description: page.data.description,
        url: page.url,
        structuredData: page.data.structuredData,
        tag: 'spec',
      })),
      ...rfcsPages.map((page) => ({
        id: page.url,
        title: page.data.title,
        description: page.data.description,
        url: page.url,
        structuredData: page.data.structuredData,
        tag: 'rfc',
      })),
    ];
  },
});
