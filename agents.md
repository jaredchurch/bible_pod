# Code Style Guidelines

## Publishing

- The contents of `public/` are deployed as an artifact, and that artifact root is served at `https://jaredchurch.github.io/bible_pod/`. A file at `public/tniv_NT.xml` is therefore reachable at `https://jaredchurch.github.io/bible_pod/tniv_NT.xml`, not at the domain root.
- `update_rss.yml` publishes two sets of feeds: the OpenDrive set in `public/` (`/bible_pod/tniv_*.xml`) and the Cloudflare R2 set in `public/rss/` (`/bible_pod/rss/tniv_*.xml`).
- The self-link a feed advertises in its `atom:link` and `link` must match where that file is actually served from. `rss.ps1` builds it from `$webBaseURL` + `$feedPath`, and `run-cloudflare.ps1` overrides only the host.

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