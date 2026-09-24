# Docs refresh for 2.4 (branch `docs/refresh-for-2.4`)

## Plan
- [x] Compile every documented Swift example (`scripts/generate-doc-snippets.py`, `scripts/check-doc-snippets.sh`, `DocSnippetsTests`), wired into CI
- [x] Rewrite 1.x-era articles for the 2.x API: Reading events, Appending events, Persistent subscriptions, Projections (→ Managing projections), Getting started
- [x] Fix Migration guide (`maxCount` → `limit`, `.continuous(name:)`, `.streamByType`, `$all` group create); split 1.x / 2.x blocks
- [x] Architecture articles: current type names, compiled ✓ examples, verified ✗ examples
- [x] Documentation.md: usage, "What's new" 2.1–2.4, article list
- [x] New article: Client pools (`KurrentDBPool`)
- [x] README, docs/index.html, CLAUDE.md, AGENTS.md, CONTRIBUTING.md
- [x] Server versions: AppendRecords is 26.1+, not 25.1+ (docs + doc comments)
- [x] Source doc-comment examples compile
- [x] Rename articles colliding with `Projections` / `Monitoring` symbols

## Review
- 183 snippets compile (`scripts/check-doc-snippets.sh` exit 0); every `✗ Compile error` example verified to fail.
- `swift build --build-tests` passes; MockClientTests (44) and KurrentCoreTests (145) pass. Integration suites not run locally (no cluster).
- DocC `--analyze`: no unresolved links in articles; remaining warnings are pre-existing ambiguous overload links in source comments.
- API made public because documented features were unusable without them: `ScavengeResponse.scavengeId/scavengeResult`, `Endpoint.host/port`, `KeepAlive` inits/properties. Added `Read.Options.resolveLinksEnabled` alias.

## Found, not fixed (behaviour changes — need a decision)
- `ClientSettings.init` defaults `discoveryInterval` to 100 µs; the connection-string default is 100 ms.
- X.509 (`userCertFile`/`userKeyFile`) is parsed but never applied to the TLS connection.
- `StreamFilter.onStreamName(prefixes:)` takes `[String]` while `onEventType(prefixes:)` is variadic.
- `Sources/KurrentDB/PersistentSubscriptions/Usecase/.swift` — a hidden-named file holding an old `GetInfo`.
