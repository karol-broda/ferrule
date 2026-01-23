import { getSpecLLMText, getRfcLLMText, specSource, rfcsSource } from '@/lib/source';

export const revalidate = false;

export async function GET() {
  const specScan = specSource.getPages().map(getSpecLLMText);
  const rfcsScan = rfcsSource.getPages().map(getRfcLLMText);
  
  const specScanned = await Promise.all(specScan);
  const rfcsScanned = await Promise.all(rfcsScan);

  return new Response([...specScanned, ...rfcsScanned].join('\n\n'));
}
