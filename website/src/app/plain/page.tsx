import Link from 'next/link';
import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'plain html docs',
  description: 'ferrule language documentation in plain html mode',
};

export default function PlainIndexPage() {
  return (
    <main>
      <h1>ferrule documentation</h1>
      
      <p>
        welcome to the plain html version of the ferrule documentation.
        this version uses minimal styling for accessibility and nostalgia.
      </p>

      <h2>documentation sections</h2>
      
      <ul>
        <li>
          <Link href="/plain/spec">language specification</Link> - 
          the complete specification for ferrule α1
        </li>
        <li>
          <Link href="/plain/rfcs">rfcs</Link> - 
          request for comments and proposed features
        </li>
      </ul>

      <h2>why plain html?</h2>
      
      <p>
        some people prefer reading documentation without fancy styling.
        this mode is:
      </p>
      
      <ul>
        <li>faster to load</li>
        <li>easier to read with screen readers</li>
        <li>works in text-based browsers</li>
        <li>nostalgic for those who remember the early web</li>
      </ul>

      <p>
        if you prefer the styled version, 
        <Link href="/spec">click here</Link>.
      </p>

      <hr />

      <p>
        <small>
          last updated: 2026
        </small>
      </p>
    </main>
  );
}
