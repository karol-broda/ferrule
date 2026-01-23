import { getSpecPageImage, specSource } from '@/lib/source';
import { notFound } from 'next/navigation';
import { ImageResponse } from 'next/og';

export const revalidate = false;

export async function GET(_req: Request, { params }: { params: Promise<{ slug: string[] }> }) {
  const { slug } = await params;
  const page = specSource.getPage(slug.slice(0, -1));
  if (page === null || page === undefined) notFound();

  const pageData = page.data as { status?: string };

  return new ImageResponse(
    (
      <div
        style={{
          display: 'flex',
          flexDirection: 'column',
          width: '100%',
          height: '100%',
          padding: '60px 80px',
          background: 'linear-gradient(135deg, #1a0a24 0%, #2d1540 50%, #1a0a24 100%)',
          color: '#f5f0fa',
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
              color: '#b84dff',
            }}
          >
            ferrule
          </span>
          <span
            style={{
              fontSize: '20px',
              color: '#9a7fad',
            }}
          >
            spec
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
                background: 'linear-gradient(135deg, #f5f0fa 0%, #d4b8e8 100%)',
                backgroundClip: 'text',
                color: 'transparent',
              }}
            >
              {page.data.title}
            </h1>
            {pageData.status !== null && pageData.status !== undefined && (
              <span
                style={{
                  fontSize: '20px',
                  padding: '6px 14px',
                  borderRadius: '6px',
                  background: 'rgba(184, 77, 255, 0.2)',
                  border: '1px solid rgba(184, 77, 255, 0.4)',
                  color: '#d4a5ff',
                }}
              >
                {pageData.status}
              </span>
            )}
          </div>

          {page.data.description !== null && page.data.description !== undefined && (
            <p
              style={{
                fontSize: '28px',
                color: '#9a7fad',
                margin: 0,
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
            borderTop: '1px solid rgba(184, 77, 255, 0.3)',
            paddingTop: '30px',
          }}
        >
          <span
            style={{
              fontSize: '18px',
              color: '#6b4f7a',
            }}
          >
            a systems language where effects and capabilities are first-class
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
  return specSource.getPages().map((page) => ({
    lang: page.locale,
    slug: getSpecPageImage(page).segments,
  }));
}
