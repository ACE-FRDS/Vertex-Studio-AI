import re

SOURCE_EXTENSIONS = (
    ".py", ".rs", ".ts", ".tsx", ".js", ".vue",
    ".md", ".toml", ".json"
)

STOP_WORDS = {
    "the","and","for","with","from","this","that","into","actual",
    "repository","mission","read","only","identify","implementation",
    "status","every","must","without","report","required"
}

def _terms(text):
    words = re.findall(r"[A-Za-z][A-Za-z0-9_-]{2,}", text or "")
    return {
        word.lower()
        for word in words
        if word.lower() not in STOP_WORDS
    }

def rank_inventory(inventory, intent, limit=24):
    terms = _terms(intent)
    ranked = []

    for item in inventory:
        path = item.get("path", "")
        size = item.get("bytes", 0)
        lower = path.lower()

        if not lower.endswith(SOURCE_EXTENSIONS):
            continue
        if size >= 200000:
            continue

        score = 0

        for term in terms:
            if term in lower:
                score += 12

        if "/src/" in lower:
            score += 4
        if "/tests/" in lower or lower.endswith("_test.rs"):
            score += 3
        if lower.endswith("cargo.toml"):
            score += 5
        if "/services/" in lower:
            score += 3

        ranked.append((score, size, path, item))

    ranked.sort(key=lambda row: (-row[0], row[1], row[2]))
    return [row[3] for row in ranked[:limit]]

def collect_evidence(workspace, inventory, intent, limit=12):
    reads = {}

    for item in rank_inventory(inventory, intent, limit=limit * 2):
        path = item["path"]
        try:
            reads[path] = workspace.read_text(path)
        except Exception:
            continue

        if len(reads) >= limit:
            break

    return reads
