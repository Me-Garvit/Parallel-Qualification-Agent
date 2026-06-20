---
name: qualification-agent
description: Qualify companies against an ICP using the Parallel API (Search + Task). Trigger ONLY when the user's message contains BOTH "parallel" AND "qualify" (or "qualification") together — e.g. "qualify these companies using parallel", "using parallel qualify these companies", "parallel qualify [csv]", "run parallel qualification". Do NOT trigger on "qualify these companies" alone without "parallel". Use this skill whenever the user explicitly invokes "parallel" as the research engine for company qualification.
---

# Parallel Qualification Agent

Qualify a CSV list of companies against an ICP using the Parallel Search API (fast, broad signals) and Parallel Task API (deep research for ambiguous cases). Output a scored CSV with reasoning and evidence URLs.

## Trigger check

Before starting, confirm the user's message contains BOTH:
- The word **parallel** (referring to the Parallel API service)  
- The word **qualify** or **qualification**

If only one is present, do not use this skill.

## Step 1 — Collect inputs

Ask the user **three questions in order**. Wait for all answers before proceeding.

1. **CSV path**: "What is the path to your CSV file? It should have columns: `name`, `domain`, `linkedin_domain`."
2. **ICP definition**: "Describe your Ideal Customer Profile in plain language. What kind of company are you looking for? (industry, size, stage, signals, etc.)"
3. **Processor**: "Which research depth do you want for deep-dive cases?

   - `base` — Fast (~30s per company). Best for large lists or quick passes.
   - `core` — Balanced (~2 min per company). Best for most use cases. *(recommended)*
   - `pro` — Deep research (~10 min per company). Best for critical decisions.
   - `ultra` — Very deep (up to 2 hrs per company). Only for high-stakes, small lists.

   Type one of: base / core / pro / ultra"

Validate the CSV exists and has the required columns (`name`, `domain`, `linkedin_domain`). If columns are missing, inform the user and stop.

Store the chosen processor — use it for every Task API call in Step 2c. If the user picks `pro` or `ultra` and the CSV has more than 10 rows, warn them upfront about the estimated time before continuing.

## Step 2 — Search all companies at once

### 2a. Batch search

Run one command — the script reads the CSV, calls Search API for every company, and returns a JSON array:

```bash
# On macOS/Linux:
python3 ~/.claude/skills/qualification-agent/tools/runner.py batch-search "<csv_path>"
# On Windows:
python3 %USERPROFILE%\.claude\skills\qualification-agent\tools\runner.py batch-search "<csv_path>"
```

Progress prints to stderr (`[1/N] searched: Company Name`). Stdout is a JSON array:

```json
[
  {
    "name": "Acme Corp",
    "domain": "acme.com",
    "search_results": [{"url": "...", "title": "...", "excerpts": ["..."]}],
    "search_error": null
  }
]
```

### 2b. Score all companies against the ICP

With the full array in hand, score every company 1–10 against the user's ICP using the search excerpts:

| Score | Meaning |
|-------|---------|
| 1–3   | Poor fit — clear disqualifiers |
| 4–6   | Ambiguous — insufficient signal |
| 7–10  | Strong fit — clear ICP match |

For each company, collect up to **3 unique evidence URLs** from `search_results[].url`. Write 1–2 sentences of reasoning grounded in the excerpts. If `search_error` is set, note the error and treat as zero results.

### 2c. Escalate score 4–6 (or zero results) to Task API

For each company with score 4–6 OR zero search results, run deep research:

```bash
# On macOS/Linux:
python3 ~/.claude/skills/qualification-agent/tools/runner.py task "<company_name>" '{"type": "json", "json_schema": {"type": "object", "properties": {"company_overview": {"type": "string", "description": "What does this company do? Industry, product, customers."}, "company_size": {"type": "string", "description": "Employee count and revenue if available. Return Unknown if not found."}, "growth_signals": {"type": "string", "description": "Recent funding, hiring trends, product launches, press coverage in past 12 months."}, "icp_fit_signals": {"type": "string", "description": "Evidence of fit or misfit with a B2B SaaS buyer ICP: pain points addressed, customer segments, deal size signals."}, "red_flags": {"type": "string", "description": "Anything that disqualifies this company: consumer focus, stealth/no web presence, competitor, wrong industry."}}, "required": ["company_overview", "company_size", "growth_signals", "icp_fit_signals", "red_flags"], "additionalProperties": false}}' "<processor>"
# On Windows:
python3 %USERPROFILE%\.claude\skills\qualification-agent\tools\runner.py task "<company_name>" '{"type": "json", "json_schema": {"type": "object", "properties": {"company_overview": {"type": "string", "description": "What does this company do? Industry, product, customers."}, "company_size": {"type": "string", "description": "Employee count and revenue if available. Return Unknown if not found."}, "growth_signals": {"type": "string", "description": "Recent funding, hiring trends, product launches, press coverage in past 12 months."}, "icp_fit_signals": {"type": "string", "description": "Evidence of fit or misfit with a B2B SaaS buyer ICP: pain points addressed, customer segments, deal size signals."}, "red_flags": {"type": "string", "description": "Anything that disqualifies this company: consumer focus, stealth/no web presence, competitor, wrong industry."}}, "required": ["company_overview", "company_size", "growth_signals", "icp_fit_signals", "red_flags"], "additionalProperties": false}}' "<processor>"
```

Replace `<processor>` with the value chosen in Step 1. The tool returns:

```json
{
  "run_id": "...",
  "content": "...",
  "citations": [{"url": "...", "title": "..."}]
}
```

Merge citation URLs into the evidence list (cap at 3 total). Re-score 1–10 using Task API content + original excerpts. Update reasoning.

### 2d. Handle errors gracefully

- If `batch-search` returns `search_error` for a company, note it in reasoning and escalate to Task API.
- If the Task API call fails, assign score = 0 with reasoning "API error — could not research."
- Never skip a company row.

## Step 3 — Write results

Once all companies are scored, build a JSON array and call `write-results` — the script creates `output/results.csv` in the user's current working directory:

```bash
# On macOS/Linux:
python3 ~/.claude/skills/qualification-agent/tools/runner.py write-results '<json_array>'
# On Windows:
python3 %USERPROFILE%\.claude\skills\qualification-agent\tools\runner.py write-results '<json_array>'
```

Where `<json_array>` is:

```json
[
  {
    "name": "Acme Corp",
    "domain": "acme.com",
    "score": 8,
    "reasoning": "Series B SaaS company targeting mid-market HR teams. Recent $20M raise and 200% YoY growth signal strong momentum.",
    "evidence_urls": ["https://techcrunch.com/acme", "https://acme.com/about"]
  }
]
```

The script writes the header row, wraps all fields in double quotes, and escapes internal quotes as `""`. On success it prints `{"output": "output/results.csv", "count": N}`.

## Step 4 — Summary

After writing the CSV, print a brief summary table:

```
Qualification complete — N companies processed

High fit (7–10):   X companies
Ambiguous (4–6):   Y companies  [N escalated to Task API]
Low fit (1–3):     Z companies
Errors (0):        W companies

Output: output/results.csv
```

Then ask: "Would you like me to show the full results table, or filter by score?"

## Tool setup

The `tools/runner.py` script requires `parallel-web` to be installed:

```bash
pip install "parallel-web>=1.0.1"
```

And `PARALLEL_API_KEY` must be set:

```bash
export PARALLEL_API_KEY="your-api-key"
# or add to tools/.env inside the skill folder
```

If the package is missing, tell the user to install it and provide the command above.

## Important constraints

- Process companies **sequentially** (not in parallel bursts) to stay within rate limits.
- The Task API `core` processor takes 60s–5min per company — warn the user upfront if the CSV has > 20 rows and Task API escalation is likely.
- Collect **at most 3 evidence URLs** per company. Prefer direct company pages and authoritative news sources over social media.
- The ICP definition the user provides is the only scoring rubric — do not impose your own criteria.
- Do not invent data. If information is unavailable, say so in the reasoning field.
