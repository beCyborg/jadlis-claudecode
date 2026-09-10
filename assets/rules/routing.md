# Tool routing (one line per intent; details live in the named skill body)

- Vault semantic search (`Знания/`) → MCP `qmd` `query`, payload form only — exact payload and rules in `Jadlis/CLAUDE.md § Semantic search`. Exact string/path → `command grep -rI`.
- Library/SDK docs → Context7 MCP.
- Web search → /search (`websearch.py`): research/news/freshness → `brave`; semantic "describe page", people/company/publication, domains/dates → `exa` (RU → `--type keyword`); `both` only on explicit request. Never native WebSearch/WebFetch. Main thread uses the script (cost log), not `mcp__exa__*`/`brave_web_search` directly.
- Page text → ladder: `defuddle parse --md` → `r.jina.ai/<url>` → `websearch.py contents <url>` → Firecrawl scrape LAST (never for PDF or x.com). Full ladder, limits, rotator → /search body "Routing details".
- PDF → `bash ~/.claude/scripts/pdf-fetch.sh <url>` then Read; hook blocks Firecrawl on PDF URLs (billed per page). Escalation → /search body.
- Scrape one page / site map / multi-URL extract → Firecrawl scrape / map / extract (via local key rotator; details → /search body).
- GitHub → /github: commit/push/PR → `/commit-commands:*`; PR review → `/code-review` (ultra for cloud); Copilot, inline comments, sub-issues → GitHub MCP; Actions/Releases/Projects → `gh`. Never scrape GitHub via Brave.
- Logged-in browser / interactive web UI → /browser (Playwright MCP, extension mode; one linear flow per session, no parallel browser subagents). Not for public scraping (→ Firecrawl).
- Native macOS apps, cross-app desktop → /computer-use, LAST resort: app MCP/CLI/API → /browser (web) → computer-use. Web tasks never via computer-use; terminal → Bash.
