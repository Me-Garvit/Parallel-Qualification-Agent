#!/usr/bin/env python3
"""CLI wrapper for Parallel Search and Task APIs.

Usage:
    python3 runner.py batch-search "<csv_path>"
    python3 runner.py task "<company_name>" "<schema>" [processor]
    python3 runner.py write-results '<json_array>'

    # Single-company search (fallback / manual use)
    python3 runner.py search "<query>"

Processors (Task API):
    base    — fast, ~30s, good for large lists
    core    — balanced, ~2 min (default)
    pro     — deep research, ~10 min
    ultra   — very deep, up to 2 hrs; append -fast for speed variants

Reads PARALLEL_API_KEY from environment or .env file.
Returns JSON to stdout; progress lines go to stderr.
"""

import sys
import os
import re
import json
import tempfile
import csv as csv_module


def _clean_excerpt(text: str) -> str:
    """Collapse markdown links to anchor text; drop empty-anchor links."""
    # Drop image links and empty-anchor links: [](url) or [![alt](src)](url)
    text = re.sub(r'\[!?\[[^\]]*\]\([^)]*\)\]\([^)]*\)', '', text)
    text = re.sub(r'\[\]\([^)]*\)', '', text)
    # Collapse [text](url) → text
    text = re.sub(r'\[([^\]]+)\]\([^)]*\)', r'\1', text)
    return text.strip()

def load_api_key() -> str:
    api_key = os.environ.get("PARALLEL_API_KEY")
    if not api_key:
        env_path = os.path.join(os.path.dirname(__file__), ".env")
        if not os.path.exists(env_path):
            env_path = os.path.join(os.path.dirname(__file__), "..", ".env")
        if os.path.exists(env_path):
            with open(env_path) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("PARALLEL_API_KEY="):
                        api_key = line.split("=", 1)[1].strip().strip('"').strip("'")
                        break
    if not api_key:
        print("Error: PARALLEL_API_KEY is not set.", file=sys.stderr)
        print("Fix: bash ~/.claude/skills/qualification-agent/setup.sh", file=sys.stderr)
        print(json.dumps({"error": "PARALLEL_API_KEY not set — run: bash ~/.claude/skills/qualification-agent/setup.sh"}))
        sys.exit(1)
    return api_key


def _normalize_columns(headers: list) -> dict:
    """Map actual CSV headers to expected column names.

    Accepts common variants so users don't need to rename columns manually.
    Returns {expected_name: actual_header} for matched columns.
    """
    variants = {
        "name":            ["name", "company name", "company_name", "company"],
        "domain":          ["domain", "company domain", "company_domain", "website", "url"],
        "linkedin_domain": ["linkedin_domain", "linkedin domain", "linkedin_url",
                            "linkedin", "linkedin url", "linkedin profile"],
    }
    headers_lower = {h.lower().strip(): h for h in headers}
    mapping = {}
    for col, alts in variants.items():
        for alt in alts:
            if alt in headers_lower:
                mapping[col] = headers_lower[alt]
                break
    return mapping


def _search_company(client, name: str, domain: str) -> dict:
    """Run Search API for one company. Returns a result entry dict."""
    query = f"{name} {domain}".strip()
    entry = {
        "name": name,
        "domain": domain,
        "search_results": [],
        "search_error": None,
    }
    try:
        search = client.search(
            objective=(
                f"Find broad signals about '{query}': recent news, product launches, "
                f"funding, customer reviews, Reddit/forum discussions, and information "
                f"from their own website. Cover a wide range of signals to enable ICP scoring."
            ),
            search_queries=[
                f"{name} {domain} company overview",
                f"{name} news funding product",
                f"{name} reviews reddit forum",
            ],
        )
        for r in search.results:
            entry["search_results"].append({
                "url": r.url,
                "title": r.title,
                "publish_date": r.publish_date,
                "excerpts": [_clean_excerpt(e) for e in r.excerpts],
            })
    except Exception as e:
        entry["search_error"] = str(e)
    return entry


def cmd_batch_search(csv_path: str) -> None:
    """Read a CSV and run Search API for every company. Returns a JSON array."""
    from parallel import Parallel

    try:
        with open(csv_path, newline="", encoding="utf-8") as f:
            reader = csv_module.DictReader(f)
            rows = list(reader)
    except FileNotFoundError:
        print(json.dumps({"error": f"CSV not found: {csv_path}"}))
        sys.exit(1)
    except Exception as e:
        print(json.dumps({"error": f"Could not read CSV: {e}"}))
        sys.exit(1)

    if not rows:
        print(json.dumps([]))
        return

    col_map = _normalize_columns(list(rows[0].keys()))
    missing = {"name", "domain", "linkedin_domain"} - set(col_map.keys())
    if missing:
        print(json.dumps({
            "error": (
                f"CSV is missing required columns: {sorted(missing)}. "
                f"Found: {list(rows[0].keys())}. "
                f"Expected (or common variants): "
                f"name/company name, domain/company domain, linkedin_domain/linkedin domain."
            )
        }))
        sys.exit(1)

    api_key = load_api_key()
    client = Parallel(api_key=api_key)

    output = []
    total = len(rows)
    for i, row in enumerate(rows, 1):
        name = row[col_map["name"]].strip()
        domain = row[col_map["domain"]].strip()
        linkedin = row[col_map["linkedin_domain"]].strip() if col_map.get("linkedin_domain") else ""

        entry = _search_company(client, name, domain)
        entry["linkedin_domain"] = linkedin
        output.append(entry)
        print(f"[{i}/{total}] searched: {name}", file=sys.stderr)

    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False, encoding="utf-8") as f:
        json.dump(output, f)
        tmp_path = f.name

    print(json.dumps({"results_file": tmp_path, "count": len(output)}))


def cmd_write_results(json_str: str) -> None:
    """Write scored results JSON array to output/results.csv in the current working directory."""
    try:
        results = json.loads(json_str)
    except json.JSONDecodeError as e:
        print(json.dumps({"error": f"Invalid JSON: {e}"}))
        sys.exit(1)

    output_dir = "output"
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, "results.csv")

    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv_module.writer(f, quoting=csv_module.QUOTE_ALL)
        writer.writerow(["name", "domain", "score", "reasoning", "evidence_urls"])
        for row in results:
            writer.writerow([
                row.get("name", ""),
                row.get("domain", ""),
                row.get("score", 0),
                row.get("reasoning", ""),
                " | ".join(row.get("evidence_urls", [])),
            ])

    print(json.dumps({"output": output_path, "count": len(results)}))


def cmd_search(query: str) -> None:
    """Single-company search (used for manual testing or fallback)."""
    from parallel import Parallel

    api_key = load_api_key()
    client = Parallel(api_key=api_key)

    try:
        search = client.search(
            objective=(
                f"Find broad signals about '{query}': recent news, product launches, "
                f"funding, customer reviews, Reddit/forum discussions, and information "
                f"from their own website. Cover a wide range of signals to enable ICP scoring."
            ),
            search_queries=[
                f"{query} company overview",
                f"{query} news funding product",
                f"{query} reviews reddit forum",
            ],
        )
        results = []
        for r in search.results:
            results.append({
                "url": r.url,
                "title": r.title,
                "publish_date": r.publish_date,
                "excerpts": [_clean_excerpt(e) for e in r.excerpts],
            })
        print(json.dumps({
            "search_id": getattr(search, "search_id", None),
            "results": results,
            "warnings": getattr(search, "warnings", None),
        }))
    except Exception as e:
        print(json.dumps({"error": str(e), "results": []}))
        sys.exit(1)


VALID_PROCESSORS = {
    "lite", "base", "core", "core2x", "pro",
    "ultra", "ultra2x", "ultra4x", "ultra8x",
    "lite-fast", "base-fast", "core-fast", "core2x-fast",
    "pro-fast", "ultra-fast",
}

def cmd_task(company_name: str, schema: str, processor: str = "core") -> None:
    """Run deep Task API research on a single company.

    schema: JSON string with the output_schema to pass to the Task API.
    processor: one of lite/base/core/core2x/pro/ultra (and -fast variants).
    """
    from parallel import Parallel

    if processor not in VALID_PROCESSORS:
        print(json.dumps({"error": f"Invalid processor '{processor}'. Valid options: {sorted(VALID_PROCESSORS)}"}))
        sys.exit(1)

    api_key = load_api_key()
    client = Parallel(api_key=api_key)

    try:
        output_schema = json.loads(schema)
    except (json.JSONDecodeError, ValueError):
        output_schema = schema

    try:
        task_run = client.task_run.create(
            input={"company": company_name},
            task_spec={"output_schema": output_schema},
            processor=processor,
        )

        result = client.task_run.result(task_run.run_id, api_timeout=600)

        citations = []
        if result.output and hasattr(result.output, "basis"):
            for field_basis in result.output.basis:
                for citation in getattr(field_basis, "citations", []) or []:
                    citations.append({
                        "url": citation.url,
                        "title": getattr(citation, "title", None),
                        "excerpts": list(getattr(citation, "excerpts", []) or []),
                    })

        content = None
        if result.output:
            content = getattr(result.output, "content", None)

        print(json.dumps({
            "run_id": task_run.run_id,
            "status": getattr(result.run, "status", "completed") if hasattr(result, "run") else "completed",
            "content": content,
            "citations": citations,
        }))

    except Exception as e:
        print(json.dumps({"error": str(e), "content": None, "citations": []}))
        sys.exit(1)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:")
        print('  python3 runner.py batch-search "<csv_path>"')
        print('  python3 runner.py task "<company_name>" "<schema>" [processor]')
        print('  python3 runner.py write-results \'[{"name":...}]\'')
        print('  python3 runner.py search "<query>"')
        sys.exit(1)

    command = sys.argv[1].lower()

    if command == "batch-search":
        if len(sys.argv) < 3:
            print(json.dumps({"error": "batch-search requires <csv_path>"}))
            sys.exit(1)
        cmd_batch_search(sys.argv[2])

    elif command == "task":
        if len(sys.argv) < 4:
            print(json.dumps({"error": "task requires <company_name> and <schema>"}))
            sys.exit(1)
        processor = sys.argv[4] if len(sys.argv) >= 5 else "core"
        cmd_task(sys.argv[2], sys.argv[3], processor)

    elif command == "write-results":
        if len(sys.argv) < 3:
            print(json.dumps({"error": "write-results requires a JSON array argument"}))
            sys.exit(1)
        cmd_write_results(sys.argv[2])

    elif command == "search":
        if len(sys.argv) < 3:
            print(json.dumps({"error": "search requires <query>"}))
            sys.exit(1)
        cmd_search(sys.argv[2])

    else:
        print(json.dumps({"error": f"Unknown command: {command}. Use batch-search, task, write-results, or search."}))
        sys.exit(1)
