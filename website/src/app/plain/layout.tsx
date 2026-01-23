import type { Metadata } from 'next';
import Link from 'next/link';

export const metadata: Metadata = {
  title: {
    default: 'ferrule (plain)',
    template: '%s | ferrule (plain)',
  },
  description: 'ferrule language documentation - plain html mode',
};

export default function PlainLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <style dangerouslySetInnerHTML={{ __html: `
        /* light mode (default) */
        body:has(.plain-wrapper) {
          background-color: #fffff8 !important;
          color: #111111 !important;
        }
        .plain-wrapper {
          font-family: "Times New Roman", Times, serif !important;
          font-size: 16px;
          line-height: 1.4;
          max-width: 800px;
          margin: 0 auto;
          padding: 20px;
          background-color: #fffff8;
          color: #111111;
          min-height: 100vh;
        }
        .plain-wrapper * {
          font-family: inherit;
        }
        .plain-wrapper a { color: #0000EE; text-decoration: underline; }
        .plain-wrapper a:visited { color: #551A8B; }
        .plain-wrapper a:hover { text-decoration: none; }
        .plain-wrapper h1, 
        .plain-wrapper h2, 
        .plain-wrapper h3, 
        .plain-wrapper h4, 
        .plain-wrapper h5, 
        .plain-wrapper h6 {
          font-weight: bold;
          margin-top: 1em;
          margin-bottom: 0.5em;
          color: #000000;
        }
        .plain-wrapper h1 { font-size: 2em; border-bottom: 1px solid #000000; padding-bottom: 0.3em; }
        .plain-wrapper h2 { font-size: 1.5em; }
        .plain-wrapper h3 { font-size: 1.17em; }
        .plain-wrapper pre {
          background-color: #f5f5dc;
          border: 1px solid #999966;
          padding: 12px;
          overflow-x: auto;
          font-family: "Courier New", Courier, monospace !important;
          font-size: 13px;
          line-height: 1.5;
        }
        .plain-wrapper code {
          font-family: "Courier New", Courier, monospace !important;
          background-color: #f5f5dc;
          padding: 2px 5px;
          color: #333300;
        }
        .plain-wrapper pre code {
          background-color: transparent;
          padding: 0;
          color: inherit;
        }
        .plain-wrapper blockquote {
          border-left: 3px solid #999966;
          margin-left: 0;
          padding-left: 15px;
          color: #444444;
          background-color: #fafaf0;
        }
        .plain-wrapper table {
          border-collapse: collapse;
          margin: 1em 0;
        }
        .plain-wrapper th, 
        .plain-wrapper td {
          border: 1px solid #000000;
          padding: 5px 10px;
          text-align: left;
        }
        .plain-wrapper th {
          background-color: #e8e8d8;
        }
        .plain-wrapper hr {
          border: none;
          border-top: 1px solid #000000;
          margin: 2em 0;
        }
        .plain-wrapper ul, 
        .plain-wrapper ol {
          padding-left: 30px;
        }
        .plain-wrapper li {
          margin-bottom: 0.3em;
        }
        .plain-wrapper p {
          margin: 1em 0;
        }
        .plain-nav-header {
          background-color: #e8e8d8;
          border: 1px solid #000000;
          padding: 10px;
          margin-bottom: 20px;
        }
        .plain-nav-header a {
          margin-right: 15px;
        }
        .plain-footer {
          margin-top: 40px;
          padding-top: 20px;
          border-top: 1px solid #999999;
          font-size: 14px;
          color: #666666;
        }
        .plain-wrapper .breadcrumb {
          font-size: 14px;
          margin-bottom: 1em;
          color: #666666;
        }
        .plain-wrapper .breadcrumb a {
          color: #0000EE;
        }
        .plain-wrapper .meta {
          font-size: 14px;
          color: #666666;
          margin-bottom: 1.5em;
        }
        .plain-mode-switch {
          float: right;
          font-size: 12px;
        }
        .plain-wrapper img {
          max-width: 100%;
        }
        .plain-wrapper strong {
          font-weight: bold;
        }
        .plain-wrapper em {
          font-style: italic;
        }
        .theme-toggle {
          background: none;
          border: 1px solid currentColor;
          padding: 2px 8px;
          font-family: inherit;
          font-size: 12px;
          cursor: pointer;
          margin-left: 10px;
        }
        .theme-toggle:hover {
          text-decoration: underline;
        }

        /* syntax highlighting - light (override all inline styles) */
        .plain-wrapper:not(.dark) figure[data-rehype-pretty-code-figure] pre,
        .plain-wrapper:not(.dark) pre[data-language],
        .plain-wrapper:not(.dark) pre {
          background-color: #f5f5dc !important;
          border: 1px solid #999966 !important;
          color: #333300 !important;
        }
        .plain-wrapper:not(.dark) figure[data-rehype-pretty-code-figure] pre::before,
        .plain-wrapper:not(.dark) pre::before {
          display: none !important;
          width: 0 !important;
          background: none !important;
        }
        .plain-wrapper:not(.dark) figure[data-rehype-pretty-code-figure] code,
        .plain-wrapper:not(.dark) pre code {
          color: #333300 !important;
          background: transparent !important;
        }
        .plain-wrapper:not(.dark) figure[data-rehype-pretty-code-figure] pre span,
        .plain-wrapper:not(.dark) figure[data-rehype-pretty-code-figure] pre code span,
        .plain-wrapper:not(.dark) pre span,
        .plain-wrapper:not(.dark) pre code span {
          color: #333300 !important;
        }
        .plain-wrapper [data-line] { display: block; }
        .plain-wrapper .line { display: inline; }

        /* dark mode */
        body:has(.plain-wrapper.dark) {
          background-color: #1a1a1a !important;
          color: #c0c0c0 !important;
        }
        .plain-wrapper.dark {
          background-color: #1a1a1a;
          color: #c0c0c0;
        }
        .plain-wrapper.dark a { color: #6699ff; }
        .plain-wrapper.dark a:visited { color: #cc99ff; }
        .plain-wrapper.dark h1,
        .plain-wrapper.dark h2,
        .plain-wrapper.dark h3,
        .plain-wrapper.dark h4,
        .plain-wrapper.dark h5,
        .plain-wrapper.dark h6 {
          color: #e0e0e0;
          border-color: #555555;
        }
        .plain-wrapper.dark pre {
          background-color: #0d0d0d;
          border-color: #333333;
          color: #00ff00;
        }
        .plain-wrapper.dark code {
          background-color: #0d0d0d;
          color: #00ff00;
        }
        .plain-wrapper.dark pre code {
          background-color: transparent;
        }
        .plain-wrapper.dark blockquote {
          border-color: #555555;
          color: #999999;
          background-color: #222222;
        }
        .plain-wrapper.dark th {
          background-color: #333333;
          color: #e0e0e0;
        }
        .plain-wrapper.dark td {
          border-color: #555555;
        }
        .plain-wrapper.dark th {
          border-color: #555555;
        }
        .plain-wrapper.dark hr {
          border-color: #555555;
        }
        .plain-wrapper.dark .plain-nav-header {
          background-color: #222222;
          border-color: #555555;
        }
        .plain-wrapper.dark .plain-footer {
          border-color: #444444;
          color: #888888;
        }
        .plain-wrapper.dark .breadcrumb,
        .plain-wrapper.dark .meta {
          color: #888888;
        }
        .plain-wrapper.dark .breadcrumb a {
          color: #6699ff;
        }

        /* syntax highlighting - dark (terminal green) */
        .plain-wrapper.dark figure[data-rehype-pretty-code-figure] pre,
        .plain-wrapper.dark pre[data-language],
        .plain-wrapper.dark pre {
          background-color: #0d0d0d !important;
          border-color: #333333 !important;
          color: #00ff00 !important;
        }
        .plain-wrapper.dark figure[data-rehype-pretty-code-figure] pre::before,
        .plain-wrapper.dark pre::before {
          display: none !important;
          width: 0 !important;
          background: none !important;
        }
        .plain-wrapper.dark figure[data-rehype-pretty-code-figure] code,
        .plain-wrapper.dark pre code {
          color: #00ff00 !important;
          background: transparent !important;
        }
        .plain-wrapper.dark figure[data-rehype-pretty-code-figure] pre span,
        .plain-wrapper.dark figure[data-rehype-pretty-code-figure] pre code span,
        .plain-wrapper.dark pre span,
        .plain-wrapper.dark pre code span {
          color: #00ff00 !important;
        }
      `}} />
      <script dangerouslySetInnerHTML={{ __html: `
        (function() {
          var saved = localStorage.getItem('plain-theme');
          if (saved === 'dark') {
            document.addEventListener('DOMContentLoaded', function() {
              var wrapper = document.querySelector('.plain-wrapper');
              if (wrapper) wrapper.classList.add('dark');
              var btn = document.getElementById('theme-toggle-btn');
              if (btn) btn.textContent = 'light mode';
            });
          }
          document.addEventListener('DOMContentLoaded', function() {
            var btn = document.getElementById('theme-toggle-btn');
            if (btn) {
              btn.addEventListener('click', function() {
                var wrapper = document.querySelector('.plain-wrapper');
                if (!wrapper) return;
                wrapper.classList.toggle('dark');
                var isDark = wrapper.classList.contains('dark');
                localStorage.setItem('plain-theme', isDark ? 'dark' : 'light');
                btn.textContent = isDark ? 'light mode' : 'dark mode';
              });
            }
          });
        })();
      `}} />
      <div className="plain-wrapper">
        <div className="plain-nav-header">
          <strong>ferrule documentation</strong>
          <span className="plain-mode-switch">
            [<Link href="/spec">styled mode</Link>]
            <button 
              type="button"
              id="theme-toggle-btn" 
              className="theme-toggle"
              dangerouslySetInnerHTML={{ __html: 'dark mode' }}
            />
          </span>
          <br />
          <Link href="/plain/spec">spec</Link>
          <Link href="/plain/rfcs">rfcs</Link>
          <Link href="/">home</Link>
        </div>
        {children}
        <div className="plain-footer">
          <hr />
          <p>
            <small>
              this page intentionally uses minimal styling for accessibility and nostalgia.
            </small>
          </p>
        </div>
      </div>
    </>
  );
}
