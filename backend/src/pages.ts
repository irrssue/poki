import type { FastifyInstance } from 'fastify';
import type { Config } from './config.ts';

// Public, static pages App Review and users need: support contact and privacy policy.
// No scripts, no external assets, no cookies: the CSP below forbids anything else.
const CSP = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";
const UPDATED = 'November 13, 2026';

const escape = (value: string) => value.replace(/[&<>"']/g, c => `&#${c.charCodeAt(0)};`);

function layout(title: string, body: string) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title} · Poki</title>
<style>
:root { color-scheme: light dark; --fg: #111; --muted: #666; --bg: #fff; --rule: #e5e5e5; }
@media (prefers-color-scheme: dark) { :root { --fg: #f2f2f2; --muted: #a0a0a0; --bg: #000; --rule: #2a2a2a; } }
body { margin: 0; background: var(--bg); color: var(--fg); font: 17px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
main { max-width: 640px; margin: 0 auto; padding: 48px 16px 64px; }
h1 { font-size: 28px; margin: 0 0 4px; }
h2 { font-size: 19px; margin: 32px 0 8px; }
p, li { margin: 0 0 10px; }
.muted { color: var(--muted); font-size: 15px; }
a { color: inherit; }
nav { margin-top: 40px; padding-top: 16px; border-top: 1px solid var(--rule); font-size: 15px; }
nav a { margin-right: 16px; }
</style>
</head>
<body><main>
${body}
<nav><a href="/support">Support</a><a href="/privacy">Privacy</a></nav>
</main></body>
</html>
`;
}

export function supportPage(supportEmail: string | undefined) {
  const contact = supportEmail
    ? `<p>Email <a href="mailto:${escape(supportEmail)}">${escape(supportEmail)}</a>. We aim to reply within two business days.</p>`
    : `<p>Use the in-app report options below. A support email address will be published here before release.</p>`;
  return layout('Support', `
<h1>Poki support</h1>
<p class="muted">Poki lets you send a small “thinking of you” poke to an accepted friend.</p>
<h2>Contact</h2>
${contact}
<h2>Report someone</h2>
<p>Reports are private; the person you report is not told. In the app you can report:</p>
<ul>
<li>a friend, from <strong>Profile → Friends → ⋯ → Report</strong>;</li>
<li>a poke or friend request, by swiping it (or long-pressing it) in your inbox;</li>
<li>a blocked person, by swiping them in <strong>Profile → Blocked</strong>;</li>
<li>a username result in <strong>Add a friend</strong>.</li>
</ul>
<p>You can also block the person in the same step. Reports are reviewed by a person, and accounts that break the rules are removed.</p>
<h2>Stop unwanted pokes</h2>
<p><strong>Mute</strong> quietly hides someone’s pokes. <strong>Remove friend</strong> ends the friendship. <strong>Block</strong> also stops them finding you or sending requests. All three are in Profile.</p>
<h2>Delete your account</h2>
<p>Open <strong>Profile → Delete account</strong>. Your profile, friends, requests, pokes and devices are deleted immediately and cannot be recovered.</p>
`);
}

export function privacyPage(supportEmail: string | undefined) {
  const contact = supportEmail
    ? `<a href="mailto:${escape(supportEmail)}">${escape(supportEmail)}</a>`
    : 'the contact listed on the <a href="/support">support page</a>';
  return layout('Privacy', `
<h1>Privacy policy</h1>
<p class="muted">Last updated ${UPDATED}</p>
<p>Poki is built to collect as little as possible. There are no ads, no tracking, no analytics and no data sales.</p>
<h2>What we store</h2>
<ul>
<li><strong>Account:</strong> you sign in with Apple. We receive an Apple account identifier and the email Apple shares (which can be a private relay address). Your name is used only to prefill your profile.</li>
<li><strong>Profile:</strong> the display name and @username you choose. Other Poki users can find you only by typing your exact username.</li>
<li><strong>Friends:</strong> friend requests, accepted friendships, blocks and mutes.</li>
<li><strong>Pokes:</strong> who poked whom, when, and the optional message of up to 30 characters.</li>
<li><strong>Notifications:</strong> if you allow them, your device’s push token, used only to deliver pokes.</li>
<li><strong>Reports:</strong> when you report someone, the reason, any details you add and a copy of the reported content.</li>
<li><strong>Favorite:</strong> your star-button setting stays on your device.</li>
</ul>
<h2>How long we keep it</h2>
<ul>
<li>Pokes are deleted 7 days after they are sent; your inbox shows the last 24 hours.</li>
<li>Pending notifications are discarded if they cannot be delivered quickly; device tokens expire after 30 days without use.</li>
<li>Resolved reports are deleted 90 days after resolution.</li>
<li>Everything else is kept until you delete your account.</li>
</ul>
<h2>Who processes it</h2>
<p>Account and social data are stored with Supabase in Canada. Notifications are delivered through Apple Push Notification service. Sign-in uses Sign in with Apple. Poki’s own server logs never contain message text, tokens or request contents.</p>
<h2>Your choices</h2>
<p>You can mute, remove or block anyone, turn notifications off in iOS Settings, and delete your account at any time from <strong>Profile → Delete account</strong>, which immediately removes your profile, friendships, pokes and devices.</p>
<h2>Children</h2>
<p>Poki is not directed at children under 13.</p>
<h2>Contact</h2>
<p>Questions about privacy: ${contact}. If this policy changes, the date above changes with it.</p>
`);
}

export function registerPages(app: FastifyInstance, config: Config) {
  const pages = { '/support': supportPage(config.supportEmail), '/privacy': privacyPage(config.supportEmail) };
  for (const [url, html] of Object.entries(pages)) {
    app.get(url, async (_request, reply) => {
      reply
        .type('text/html; charset=utf-8')
        .header('Content-Security-Policy', CSP)
        .header('X-Content-Type-Options', 'nosniff')
        .header('Referrer-Policy', 'no-referrer')
        .header('Cache-Control', 'public, max-age=300');
      return html;
    });
  }
}
