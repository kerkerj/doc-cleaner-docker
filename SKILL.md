---
name: doc-cleaner-docker
description: Convert PDF, DOCX, XLSX, PPTX, EPUB, Keynote/Numbers files to clean Markdown using the doc-cleaner Docker container. CJK-friendly, table-friendly, no host Python/Java needed. Use when the user wants to convert documents to Markdown and the doc-cleaner:local image is available.
version: 1.0.0
metadata: {"openclaw":{"emoji":"📄","homepage":"https://github.com/kerkerj/doc-cleaner-docker","requires":{"bins":["docker"]}}}
---

# doc-cleaner (Docker)

Convert documents (PDF, DOCX, XLSX, EPUB, Keynote…) to clean, structured Markdown
via the `doc-cleaner:local` Docker image. No Python / Java / poppler needed on the host.

## When to use

- User asks to convert a document to Markdown
- User wants to extract text or tables from PDF/DOCX/XLSX files
- User wants to process a batch of documents in a directory

## Prerequisites

The `doc-cleaner:local` image must exist (`docker image inspect doc-cleaner:local`).
If missing, build it from this repo:

```bash
cd <this-repo> && docker compose build
```

## Commands

Mount the file's directory read-only at `/data`, and an output directory at `/app/out`.

### Convert a single file (no AI, fastest, fully local)
```bash
docker run --rm \
  -v "<dir-containing-file>:/data:ro" \
  -v "<output-dir>:/app/out" \
  doc-cleaner:local -i "/data/<filename>" --ai none
```

### Convert all files in a directory
```bash
docker run --rm \
  -v "<input-dir>:/data:ro" \
  -v "<output-dir>:/app/out" \
  doc-cleaner:local -i /data --ai none
```

### Encrypted PDF (bank statements, ETC reports…)

Encrypted PDFs are common (Taiwan bank statements, ETC reports — password is usually
the owner's ID number, uppercase). If a run fails with
`'xxx.pdf' is password-protected. Use --password option.`,
ASK THE USER for the password, then retry with it — don't give up or guess:

```bash
docker run --rm \
  -v "<dir>:/data:ro" -v "<out>:/app/out" \
  doc-cleaner:local -i "/data/<filename>" --password "<password>" --ai none
```

Or pass `-e PDF_PASSWORD=<password>` instead of `--password` (keeps it out of the command line).
One password per run — batch files with different passwords separately.
The decrypted temp copy stays inside the container and is discarded on exit.

### With Gemini / Groq structuring (needs API key)
```bash
docker run --rm \
  -v "<dir>:/data:ro" -v "<out>:/app/out" \
  -e GEMINI_API_KEY \
  doc-cleaner:local -i "/data/<filename>" --ai gemini
```

### With local Ollama on the host
```bash
docker run --rm \
  -v "<dir>:/data:ro" -v "<out>:/app/out" \
  --add-host host.docker.internal:host-gateway \
  -e OLLAMA_HOST=http://host.docker.internal:11434 \
  doc-cleaner:local -i "/data/<filename>" --ai ollama
```

### Clean email bodies / plain text (needs AI mode)

Email bodies (bank notifications, newsletters…) can be converted too: save the body
as a `.txt` file in the input dir. IMPORTANT: with `--ai none`, txt is passed through
as-is — the built-in ad-truncation only runs on the PDF path. To actually strip
boilerplate (legal footers, marketing) and rebuild flattened tables, use an AI backend:

```bash
docker run --rm \
  -v "<dir>:/data:ro" -v "<out>:/app/out" \
  -e GEMINI_API_KEY \
  doc-cleaner:local -i "/data/<email>.txt" --config /data/config.json --ai gemini
```

With a free-tier Gemini key, the default model `gemini-2.5-pro` has ZERO quota
(instant 429). Put this config.json in the input dir and pass `--config /data/config.json`:

```json
{ "ai": { "gemini": { "model": "gemini-2.5-flash" } } }
```

The AI output includes frontmatter (title, summary, tags) — ready for Obsidian.

### Machine-readable result summary
Append `--summary` — prints a JSON summary to stdout:
```json
{"version":"1.6.0","total":1,"success":1,"failed":0,"files":[{"file":"report.pdf","output":"/app/out/report.md","status":"ok"}]}
```

## Notes

- Output `.md` files land in the mounted output dir, owned by UID 1000
- Exit codes: `0` all ok · `1` partial failure · `2` no processable files / config error
- `--ai none` needs zero API keys and zero network
- Scanned PDFs need an AI backend (`gemini` / `groq` / `ollama`) for good results
- **Supported formats**: PDF (native/scanned/encrypted), DOCX, XLSX, XLS, CSV, PPTX,
  EPUB, Keynote (.key), Numbers, DXF, TXT, MD, JSONL
- **Not supported**: PPT / DOC / PAGES (need macOS system tools, impossible in Linux)
- The output dir must be writable by UID 1000 (or rebuild with matching `APP_UID`/`APP_GID`)
