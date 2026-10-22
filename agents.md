# Code Style Guidelines

## Publishing

- The contents of `public/` are deployed as an artifact, and that artifact root is served at `https://jaredchurch.github.io/bible_pod/`. A file at `public/tniv_NT.xml` is therefore reachable at `https://jaredchurch.github.io/bible_pod/tniv_NT.xml`, not at the domain root.
- `update_rss.yml` generates the feeds from the Cloudflare R2 bucket only. The OpenDrive backend (`src/run.ps1`) is disabled in CI and its step is kept commented out, so it can be switched back on.
- The R2 feeds are published twice, from the same files: in `public/` (`/bible_pod/tniv_*.xml`, where the OpenDrive set used to be served) and in `public/rss/` (`/bible_pod/rss/tniv_*.xml`). The root copy keeps the pre-existing URLs resolving.
- The self-link a feed advertises in its `atom:link` and `link` must match where that file is actually served from. `rss.ps1` builds it from `$webBaseURL` + `$feedPath`, and `run-cloudflare.ps1` overrides only the host.
- Disabling the OpenDrive backend also stops the `put-xml` upload inside `src/run.ps1`, which is what publishes `www.opendrive.com/bible_pod/rss/tniv_*.xml`. That is the URL the podcast apps are subscribed to, so it needs repointing at a GitHub Pages feed.

## Headers

All script and source files must include a header with:
- Filename
- Purpose/description
- Author (optional)
- Date created (optional)

Example for Bash:
```bash
#!/bin/bash
#######################################################################
#
#   FileName: run.sh
#
#   Purpose: Executes the main script and compares output
#
#######################################################################
```

Example for PowerShell:
```powershell
#######################################################################
#
#   FileName: run.ps1
#
#   Purpose: Updates RSS Feed
#
#######################################################################
```

## Comments

- Add comments to explain **why** something is done, not **what** is being done
- Keep comments brief and concise
- Comment complex logic, business rules, or non-obvious decisions
- Avoid obvious or redundant comments
- Comment edge cases or workarounds