#!/bin/bash
# =============================================================================
# Dev Container Post-Create Script
# =============================================================================
# This script runs automatically after the dev container is created.
# It sets up the development environment with required tools and dependencies.
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# Install Node.js and npm if not already available
# -----------------------------------------------------------------------------
sudo apt-get update
sudo apt-get install -y npm

# Install opencode-ai CLI tool globally for AI-assisted development
npm install -g opencode-ai@latest

# Configure opencode-ai to use the big-pickle model by default
mkdir -p ~/.config/opencode
echo '{
  "$schema": "https://opencode.ai/config.json",
  "model": "opencode/big-pickle"
}' > ~/.config/opencode/config.json

# Change vscode user's default shell to PowerShell for consistent experience
sudo chsh vscode -s "$(which pwsh)"

# Install GitHub CLI (gh) for managing GitHub operations from terminal
curl -fsSL https://github.com/cli/cli/releases/download/v2.34.0/gh_2.34.0_linux_amd64.tar.gz -o ghcli.tar.gz
tar -xzf ghcli.tar.gz
sudo mv gh_2.34.0_linux_amd64/bin/gh /usr/local/bin/gh
rm -rf ghcli.tar.gz gh_2.34.0_linux_amd64


### End of File
