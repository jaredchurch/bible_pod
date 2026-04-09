# Code Style Guidelines

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