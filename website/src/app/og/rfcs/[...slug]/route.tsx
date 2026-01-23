import { getRfcPageImage, rfcsSource } from '@/lib/source';
import { notFound } from 'next/navigation';
import { ImageResponse } from 'next/og';

export const revalidate = false;

export async function GET(_req: Request, { params }: { params: Promise<{ slug: string[] }> }) {
  const { slug } = await params;
  const page = rfcsSource.getPage(slug.slice(0, -1));
  if (page === null || page === undefined) notFound();

  const pageData = page.data as { rfc?: string | number; status?: string; target?: string };
  const rfcNumber = pageData.rfc !== null && pageData.rfc !== undefined
    ? `RFC-${String(pageData.rfc).padStart(4, '0')}`
    : null;

  return new ImageResponse(
    (
      <div
        style={{
          display: 'flex',
          flexDirection: 'column',
          width: '100%',
          height: '100%',
          padding: '60px 80px',
          background: 'linear-gradient(135deg, #1a1408 0%, #3d2a10 50%, #1a1408 100%)',
          color: '#faf5f0',
          fontFamily: 'system-ui, sans-serif',
        }}
      >
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '12px',
            marginBottom: '40px',
          }}
        >
          <span
            style={{
              fontSize: '28px',
              fontWeight: 600,
              color: '#f59e0b',
            }}
          >
            ferrule
          </span>
          <span
            style={{
              fontSize: '20px',
              color: '#ad8f5f',
            }}
          >
            rfc
          </span>
        </div>

        <div
          style={{
            display: 'flex',
            flexDirection: 'column',
            flex: 1,
            justifyContent: 'center',
          }}
        >
          {rfcNumber !== null && (
            <span
              style={{
                fontSize: '24px',
                color: '#f59e0b',
                fontFamily: 'monospace',
                marginBottom: '12px',
              }}
            >
              {rfcNumber}
            </span>
          )}
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '16px',
              marginBottom: '20px',
            }}
          >
            <h1
              style={{
                fontSize: '64px',
                fontWeight: 700,
                lineHeight: 1.1,
                margin: 0,
                background: 'linear-gradient(135deg, #faf5f0 0%, #e8d4b8 100%)',
                backgroundClip: 'text',
                color: 'transparent',
              }}
            >
              {page.data.title}
            </h1>
          </div>

          <div
            style={{
              display: 'flex',
              gap: '12px',
            }}
          >
            {pageData.status !== null && pageData.status !== undefined && (
              <span
                style={{
                  fontSize: '20px',
                  padding: '6px 14px',
                  borderRadius: '6px',
                  background: 'rgba(245, 158, 11, 0.2)',
                  border: '1px solid rgba(245, 158, 11, 0.4)',
                  color: '#fbbf24',
                }}
              >
                {pageData.status}
              </span>
            )}
            {pageData.target !== null && pageData.target !== undefined && (
              <span
                style={{
                  fontSize: '20px',
                  padding: '6px 14px',
                  borderRadius: '6px',
                  background: 'rgba(139, 92, 246, 0.2)',
                  border: '1px solid rgba(139, 92, 246, 0.4)',
                  color: '#a78bfa',
                }}
              >
                target: {pageData.target}
              </span>
            )}
          </div>

          {page.data.description !== null && page.data.description !== undefined && (
            <p
              style={{
                fontSize: '28px',
                color: '#ad8f5f',
                margin: 0,
                marginTop: '20px',
                lineHeight: 1.4,
                maxWidth: '900px',
              }}
            >
              {page.data.description}
            </p>
          )}
        </div>

        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            borderTop: '1px solid rgba(245, 158, 11, 0.3)',
            paddingTop: '30px',
          }}
        >
          <span
            style={{
              fontSize: '18px',
              color: '#7a5f3a',
            }}
          >
            ferrule language rfcs — proposed features
          </span>
        </div>
      </div>
    ),
    {
      width: 1200,
      height: 630,
    },
  );
}

export function generateStaticParams() {
  return rfcsSource.getPages().map((page) => ({
    lang: page.locale,
    slug: getRfcPageImage(page).segments,
  }));
}
