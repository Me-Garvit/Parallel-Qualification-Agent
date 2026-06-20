# qualification-agent

A Claude Code skill that qualifies a list of companies against an Ideal Customer Profile (ICP) using the [Parallel API](https://parallel.ai) — Search for broad signals, Task API for deep research on ambiguous cases.

## Setup

**macOS / Linux** — paste this in Terminal:
```bash
curl -fsSL https://raw.githubusercontent.com/garvit-exe/qualification-agent/main/install.sh | bash
```

**Windows** — paste this in PowerShell:
```powershell
irm https://raw.githubusercontent.com/garvit-exe/qualification-agent/main/install.ps1 | iex
```

Both installers handle everything: installing prerequisites, cloning the skill, installing dependencies, and saving your API key. Get your Parallel API key at [platform.parallel.ai](https://platform.parallel.ai).

## Usage

1. Open a terminal in the folder containing your CSV
2. Run `claude`
3. Say something like:

```
parallel qualify companies.csv
```

Claude will ask for three things:
1. **CSV path** — path to your companies file
2. **ICP** — describe your ideal customer in plain language (industry, size, stage, signals, etc.)
3. **Processor** — how deep to research ambiguous companies:
   - `base` — ~30s per company, good for large lists
   - `core` — ~2 min per company, best for most use cases *(recommended)*
   - `pro` — ~10 min per company, best for critical decisions
   - `ultra` — up to 2 hrs per company, for high-stakes small lists

Results are written to `output/results.csv` in your current folder.

## Input CSV

Your CSV needs at least these columns (flexible naming accepted):

| Accepted names | Maps to |
|---|---|
| `name`, `company name`, `company_name` | Company name |
| `domain`, `company domain`, `website` | Website domain |
| `linkedin_domain`, `linkedin domain`, `linkedin` | LinkedIn URL |

Example:
```csv
name,domain,linkedin_domain
Acme Corp,acme.com,linkedin.com/company/acme
```

## Output CSV

```csv
name,domain,score,reasoning,evidence_urls
"Acme Corp","acme.com",8,"Series B SaaS targeting mid-market HR. $20M raise, 200% YoY growth.","https://... | https://..."
```

Scores: **1–3** low fit · **4–6** ambiguous (escalated to Task API) · **7–10** strong fit

## How it works

1. **Batch search** — Parallel Search API runs for every company at once, returning news, funding, reviews, and product signals
2. **ICP scoring** — Claude scores each company 1–10 against your ICP using the search excerpts
3. **Deep research** — Ambiguous companies (score 4–6) are escalated to the Parallel Task API for deeper investigation and re-scored
4. **Results** — Written to `output/results.csv` with score, reasoning, and up to 3 evidence URLs per company

## Folder structure

```
qualification-agent/
├── SKILL.md              # Skill definition loaded by Claude Code
├── README.md             # This file
├── install.sh            # macOS/Linux one-command installer
├── install.ps1           # Windows one-command installer
├── setup.sh              # macOS/Linux setup (post-clone)
├── setup.ps1             # Windows setup (post-clone)
├── tools/
│   ├── runner.py         # CLI wrapper for Parallel Search + Task APIs
│   └── .env.example      # API key template
└── references/
    └── parallel-ai.md    # Parallel API documentation
```

> `output/` is created at runtime in your working directory, not inside the skill folder.
