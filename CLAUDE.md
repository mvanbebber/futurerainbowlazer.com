# Notes for Claude

## Writing style
- The owner is American: use **American English** everywhere (app text, landing pages, posts, emails, commit
  messages), e.g. practice (never "practise"), license, color, center, favorite, analyze.

## Slow Down Buddy (web app in `deploy/`)
- Hosted on Netlify from this branch; every deploy costs Netlify credits. Batch changes and push only when the
  owner has approved a set of them. Pushes that don't touch `deploy/` or `netlify.toml` skip the build.
- No build step: `deploy/index.html` is the whole app (inline CSS/JS plus the Signalsmith Stretch library);
  decoders (`flac-decoder.min.js`, `m4a-decoder.js`, `opus-decoder.min.js`) load on demand.
- Guide pages (`deploy/*/index.html`) share `deploy/guides.css`; keep `deploy/sitemap.xml` in step with them.
- Test locally with `python3 -m http.server` in `deploy/` and Playwright (Chromium is preinstalled).
