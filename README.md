# doc-cleaner-docker

[doc-cleaner](https://github.com/notoriouslab/doc-cleaner)（日常文件轉 Markdown）的 **Linux 容器打包**：
一次性 CLI，掛 volume 跑完就退，主力處理 PDF。

這個 repo 只放打包相關的檔案 —— 原始碼在 build 階段從上游 public repo clone（原封不動），
clone 這個 repo 就能 build，支援 linux/arm64 與 amd64。

---

## 快速開始

不想本地 build 的話，直接拉現成 image（push 到 main 時 CI 自動 build，arm64 + amd64）：

```bash
docker pull ghcr.io/kerkerj/doc-cleaner-docker:latest
```

本地 build：

```bash
git clone https://github.com/kerkerj/doc-cleaner-docker.git && cd doc-cleaner-docker
mkdir -p input output
docker compose build

# 把要處理的檔案丟進 ./input，產出會出現在 ./output
docker compose run --rm doc-cleaner -i /data/report.pdf --ai none
```

- 輸入掛在 `/data`（唯讀），輸出固定寫到 `/app/out`（對應 host 的 `./output`）
- 容器已內建 Java（ODL 表格提取）與 poppler（掃描 vision 模式）
- AI backend 的 key 用 `.env` 傳（參考上游 `.env.example`），`--ai none` 時不需要

### 加密 PDF（對帳單、ETC 報表這類）

三種給密碼的方式：

```bash
# 方式 1：CLI 參數（一次性，最直覺）
docker compose run --rm doc-cleaner -i /data/statement.pdf --password 'A123456789' --ai none

# 方式 2：環境變數（不想讓密碼進 shell history 的話搭配 read -s 使用）
docker compose run --rm -e PDF_PASSWORD='A123456789' doc-cleaner -i /data/statement.pdf --ai none

# 方式 3：寫在 .env（密碼固定時最方便，例如都是自己的身分證字號）
echo 'PDF_PASSWORD=A123456789' >> .env
docker compose run --rm doc-cleaner -i /data/statement.pdf --ai none
```

- 優先順序：`--password` > `.env` / 環境變數
- 一次執行只能一組密碼；不同檔案不同密碼就分次跑
- 解密後的暫存檔在容器內的工作區，跑完就消失，不會留在 `input/`
- `.env` 已在 `.gitignore`，不會進版控

### 清洗信件本文（銀行通知這類）

信件本文存成 `.txt` 丟進 `input/` 也能轉。注意：**`--ai none` 對 txt 是直通**
（上游的廣告清洗只接在 PDF 路徑），要濾掉法律聲明、重建被壓扁的表格得走 AI 模式：

```bash
# free tier 的 Gemini 預設模型 gemini-2.5-pro 配額是 0（秒 429），
# 要在 config 指定 flash：input/config.json 放 {"ai":{"gemini":{"model":"gemini-2.5-flash"}}}
docker compose run --rm -e GEMINI_API_KEY doc-cleaner \
  -i /data/mail.txt --config /data/config.json --ai gemini
```

輸出自帶 frontmatter（標題/摘要/tags），可直接進 Obsidian。

### 用 Ollama

Ollama server 跑在 host（不在容器內），compose 已把 `OLLAMA_HOST` 指向
`host.docker.internal`，Mac / Linux Desktop 都直接可用：

```bash
docker compose run --rm doc-cleaner -i /data/report.pdf --ai ollama
```

### 支援格式（上游 16 種中的 14 種）

| 類別 | 格式 | 備註 |
|------|------|------|
| PDF | 原生 / 掃描 / 加密 | 原生含 ODL 表格提取；掃描要搭 AI backend；加密用 `--password` |
| Office | DOCX、XLSX、XLS、CSV、PPTX | DOCX/XLSX/PPTX 表格轉 pipe table |
| Apple | Keynote（.key）、Numbers | |
| 電子書 | EPUB | |
| 工程圖 | DXF | |
| 純文字 | TXT、MD、JSONL | |

**不支援：** PPT / DOC / PAGES —— 上游處理這三種格式靠 macOS 系統工具
（textutil / QuickLook），Linux 容器內拿不到。

---

## 上游更新後怎麼重建

```bash
# clone 那層有 cache，要吃到上游新 commit 得 --no-cache
# （或把 compose 裡的 DOC_CLEANER_REF 改成新的 tag / commit 再普通 build）
docker compose build --no-cache

# 跑一份測試 PDF 確認沒壞
docker compose run --rm doc-cleaner -i /data/<某檔>.pdf --ai none --verbose
```

`--verbose` 時留意分流結果：有表格的原生 PDF 應該走
「**Native PDF via ODL (tables detected)**」，如果退回 PyMuPDF 表示 ODL 路徑壞了。

---

## 當 Claude Code skill 用

repo 附帶 `SKILL.md`（Docker 版），讓任何 Claude Code session 都能直接叫容器轉檔：

```bash
ln -sfn "$(pwd)" ~/.claude/skills/doc-cleaner-docker
```

前提：該機器上 image 已 build 好（`docker compose build`）。

---

## 設計說明

- **一次性 CLI**：掛 volume、跑完就退，不是常駐服務。
- **內建 Java + poppler**：Java 給 opendataloader-pdf 做表格提取、poppler 給掃描 PDF 的
  vision 模式，image 約 765MB。不需要表格提取的話，可以自行 fork 拿掉
  `default-jre-headless` 和 `opendataloader-pdf`，能縮到約 300MB。
- **AI backend 不綁定**：gemini / groq / ollama / none 都能跑，key 用環境變數傳，
  image 裡不含任何金鑰。
- **非 root 執行**：UID/GID 預設 1000，可用 `--build-arg APP_UID=<uid> APP_GID=<gid>`
  對齊宿主帳號，輸出檔的 owner 才不會是 root。
- **上游程式碼原封不動**：build 時 clone、不 vendor、不套 patch，
  更新只要 `--no-cache` 重 build 就拿到上游新版。

兩個不那麼直覺、但動 Dockerfile / compose / entrypoint 前需要知道的地方：

1. **輸出掛 `/app/out` 而不是預設的 `./output`**：上游 repo 的 `output/` 是
   Python package（`cleaner.py` 會 import），volume 掛在 `/app/output` 會把它蓋掉、
   容器直接 crash。這也是 entrypoint 固定帶 `-o /app/out` 的原因。
2. **entrypoint 會先把 `/data` 複製到容器內的 `/work` 再處理**：
   opendataloader-pdf 會把暫存 `.md` 寫在輸入檔旁邊，輸入掛唯讀直接跑會失敗、
   默默退回 PyMuPDF（表格品質差很多）。複製一份處理，暫存檔隨容器退出消失，
   原始檔不被碰，輸入 mount 得以維持 `:ro`。

---

## 部署備註

- **離線環境**：ODL 的 Java jar 已隨 pip wheel 打包（不是執行時下載），
  理論上斷網可跑，正式離線部署前建議先實測。
- **NAS**：在 NAS 上 `host.docker.internal` 會指向 NAS 自己，用 Ollama 的話
  要把 `OLLAMA_HOST` 改成 Ollama 所在機器的 IP；build 時帶 NAS 宿主的 UID/GID。

