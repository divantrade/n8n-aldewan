# CLAUDE.md - Project Context for Claude Code

## Project: n8n-aldewan

Git-based deployment pipeline for n8n workflows at Aldewan (الديوان).
Syncs workflow JSON files from this GitHub repo to a self-hosted n8n instance.

## Architecture

```
GitHub (workflows/*.json) --push to main--> GitHub Actions --> n8n REST API (PUT /api/v1/workflows/{id})
```

- **n8n instance**: Self-hosted with SSL (URL stored in GitHub secret `N8N_URL`)
- **Authentication**: API key stored in GitHub secret `N8N_API_KEY`
- **Deploy script**: `.github/workflows/deploy-n8n.yml`

## Current State (as of Feb 2026)

**CI/CD pipeline is FULLY WORKING.**

- Auto-deploy triggers on push to `main` when `workflows/*.json` files change
- Also triggers when the deploy script itself (`.github/workflows/deploy-n8n.yml`) changes
- Manual deploy available via `workflow_dispatch` (force_all or specific file)
- All 11 workflows deploy successfully to n8n

## Key Technical Decisions

1. **SSL**: Uses `curl -k` to allow self-signed certificates on the n8n server
2. **API payload**: Uses jq **whitelist** approach `{name, nodes, connections, settings, staticData}` - only sends fields the n8n API accepts. Do NOT use blacklist/del() approach as the API rejects unknown fields with HTTP 400.
3. **Large files**: Payload is written to `/tmp/payload.json` and sent via `curl -d @/tmp/payload.json` to avoid "Argument list too long" errors (the largest workflow `tax-receipts-production.json` is ~437KB).
4. **Tags**: Tags are NOT sent in the API payload because n8n's API treats them as read-only on the PUT endpoint.

## Workflow Files

All in `workflows/` directory. Each JSON file contains a full n8n workflow export with an `id` field that maps to the workflow ID in n8n.

## Issues Resolved During Setup

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| SSL error (exit code 60) | Self-signed cert on n8n server | Added `curl -k` flag |
| HTTP 400 "tags is read-only" | Sending `tags` array in PUT body | Removed tags from payload |
| HTTP 400 "additional properties" | Sending `meta`, `pinData`, etc. | Switched to whitelist: `{name, nodes, connections, settings, staticData}` |
| "Argument list too long" | 437KB JSON as shell variable in curl `-d` | Write to temp file, use `curl -d @file` |
| Action not triggering on script changes | `paths:` filter only had `workflows/*.json` | Added `.github/workflows/deploy-n8n.yml` to paths |

## Commands

- `./scripts/sync.sh pull` - Pull all workflows from n8n to local
- `./scripts/sync.sh push` - Push workflows to n8n (injects code automatically)
- `./scripts/sync.sh extract-code` - Extract Code nodes as .js/.py files
- Manual GitHub Actions dispatch available for selective deployment
