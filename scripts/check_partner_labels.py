#!/usr/bin/env python3
"""Partner-label gate for the rendered demo deliverables (stdlib only).

Fails if a real trading-partner name appears in a rendered demo deliverable.
Every deliverable puts partners beside Cinderhaven dollar figures, so the demo
shows role labels instead (R/engagement.R, DECISIONS 2026-11-16).

Scans: quarto/report.html, quarto/dashboard.html, quarto/tearsheet.pdf,
output/scorecard.pdf, output/*_audit.xlsx, output/charts/*.svg and the frame
CSVs (raw tables excluded). The compliance timeline is not scanned: it cites
retailers' own published requirements and carries no Cinderhaven figure.

Run after the pipeline: python3 scripts/check_partner_labels.py
"""
import glob
import html
import os
import re
import shutil
import subprocess
import sys
import zipfile

REAL = re.compile(r"\b(Walmart|Costco|Whole Foods|Kroger|Sprouts|UNFI|KeHE|DPI Northwest)\b")
LABELS = ["National mass retailer", "Club retailer", "Natural grocer",
          "Conventional grocer", "Regional natural grocer"]


def text_of(path: str) -> str | None:
    if path.endswith(".pdf"):
        if not shutil.which("pdftotext"):
            return None
        return subprocess.run(["pdftotext", "-layout", path, "-"],
                              capture_output=True, text=True).stdout
    if path.endswith(".xlsx"):
        parts = []
        with zipfile.ZipFile(path) as z:
            for name in z.namelist():
                if name.endswith(".xml"):
                    parts.append(z.read(name).decode("utf-8", "replace"))
        return html.unescape(re.sub(r"<[^>]+>", " ", " ".join(parts)))
    with open(path, encoding="utf-8", errors="replace") as fh:
        raw = fh.read()
    if path.endswith((".html", ".svg")):
        raw = re.sub(r"<script\b.*?</script>", lambda m: m.group(0), raw, flags=re.S)
        return html.unescape(raw)
    return raw


def main() -> int:
    targets = ["quarto/report.html", "quarto/dashboard.html", "quarto/tearsheet.pdf",
               "output/scorecard.pdf"]
    targets += sorted(glob.glob("output/*_audit.xlsx"))
    targets += sorted(glob.glob("output/charts/*.svg"))
    targets += sorted(p for p in glob.glob("output/frames/*.csv"))
    failed = False
    scanned = 0
    for path in targets:
        if not os.path.exists(path):
            print(f"::warning::partner-label gate: missing {path}")
            continue
        text = text_of(path)
        if text is None:
            print(f"::warning::partner-label gate: cannot read {path} (pdftotext not installed)")
            continue
        scanned += 1
        hits = REAL.findall(text)
        if hits:
            failed = True
            counts = {h: hits.count(h) for h in sorted(set(hits))}
            sample = REAL.search(text)
            ctx = " ".join(text[max(0, sample.start() - 70): sample.end() + 70].split())
            print(f"::error::partner-label gate: {path} names real partners {counts}. First: ...{ctx}...")
    for path in ("quarto/report.html", "quarto/dashboard.html"):
        if os.path.exists(path):
            text = text_of(path) or ""
            counts = {lab: text.count(lab) for lab in LABELS}
            print(f"::notice::partner-label gate: {path} label counts {counts}")
            # The report covers the whole roster; the dashboard shows only the
            # contracted subset, so it need only carry some labels.
            ok = all(counts.values()) if path.endswith("report.html") else any(counts.values())
            if not ok:
                failed = True
                print(f"::error::partner-label gate: {path} is missing role labels {counts}")
    print(f"partner-label gate: scanned {scanned} files, {'FAILED' if failed else 'clean'}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
