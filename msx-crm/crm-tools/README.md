# CRM Tools

MSX CRM (Dynamics 365) helper script bundled with the `/msx-crm` skill.

## Location

After running `install.sh` / `install.ps1`, this folder is accessible at:
- **macOS/Linux:** `~/.copilot/skills/msx-crm/crm-tools/`
- **Windows:** `$HOME\.copilot\skills\msx-crm\crm-tools\`

## Setup

The install script handles MCAPS-IQ cloning automatically. To do it manually:

```bash
# macOS / Linux
cd ~/.copilot/skills/msx-crm/crm-tools
git clone https://github.com/yingding/MCAPS-IQ.git lib/mcaps-iq

# Windows PowerShell
Set-Location "$HOME\.copilot\skills\msx-crm\crm-tools"
git clone https://github.com/yingding/MCAPS-IQ.git lib\mcaps-iq
```

## Verify

```bash
node ~/.copilot/skills/msx-crm/crm-tools/run-tool.mjs
# Should print: Available tools: crm_whoami, crm_auth_status, ...
```

## Available Tools

| Tool | Description |
|------|-------------|
| `crm_whoami` | Get current user's CRM identity |
| `crm_auth_status` | Check authentication status |
| `crm_query` | Raw OData query against any CRM entity |
| `list_opportunities` | Search opportunities by customer keyword |
| `get_my_active_opportunities` | List your active opportunities |
| `get_milestones` | Get milestones for an opportunity or customer |
| `get_milestone_activities` | List tasks on a milestone |
| `find_milestones_needing_tasks` | Find milestones with no recent tasks |
| `create_task` | Create a CRM task on a milestone |
| `update_task` | Update an existing CRM task |
| `delete_task` | Delete a CRM task |

## Usage

```bash
node ~/.copilot/skills/msx-crm/crm-tools/run-tool.mjs <tool-name> '<json-params>'

# Examples:
node ~/.copilot/skills/msx-crm/crm-tools/run-tool.mjs get_milestones '{"customerKeyword":"Contoso"}'
node ~/.copilot/skills/msx-crm/crm-tools/run-tool.mjs list_opportunities '{"customerKeyword":"Fabrikam"}'
```
