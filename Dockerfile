# doc-cleaner — 日常文件轉 Markdown（Linux 容器版）
# 配置：中等（PDF 表格/掃描）+ AI backend 全保留彈性
# 目標平台：linux/arm64（Apple Silicon M1/M4 已實測）；amd64 亦可 build
#
# 原始碼在 build 階段從上游 public repo clone（原封不動，不套 patch），
# 這個 repo 只放打包相關的檔案。更新上游 = docker compose build --no-cache。

# --- Stage 1：抓上游原始碼 ---
FROM python:3.12-slim AS src
ARG DOC_CLEANER_REPO=https://github.com/notoriouslab/doc-cleaner.git
ARG DOC_CLEANER_REF=main
RUN apt-get update && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/* \
    && git clone --depth 1 --branch ${DOC_CLEANER_REF} ${DOC_CLEANER_REPO} /src \
    && rm -rf /src/.git

# --- Stage 2：runtime ---
FROM python:3.12-slim

# default-jre-headless: opendataloader-pdf 需要 Java 11+（高品質 PDF 表格提取）
# poppler-utils:        pdf2image 需要（掃描 PDF 的 vision 模式）
RUN apt-get update && apt-get install -y --no-install-recommends \
        default-jre-headless \
        poppler-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# --- pip 第 1 層：核心依賴（requirements.txt 沒變就吃 cache）---
COPY --from=src /src/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# --- pip 第 2 層：optional 功能 ---
# PDF 進階：opendataloader-pdf(表格) / pdf2image(掃描) / pikepdf(解密)
# 額外格式：python-pptx(PPTX) / ezdxf(DXF 工程圖)
# AI backend：google-genai(gemini) / ollama / python-dotenv / certifi(groq)
RUN pip install --no-cache-dir \
        opendataloader-pdf pdf2image pikepdf \
        python-pptx ezdxf \
        google-genai ollama python-dotenv certifi

# --- 應用程式原始碼 ---
COPY --from=src /src /app

# --- 輸入複製 wrapper：詳見 entrypoint.sh 開頭的說明 ---
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# --- 非 root 使用者（讓輸出檔 owner 乾淨，好對接 NAS / 自動化流程）---
# UID/GID 預設 1000；可用 --build-arg APP_UID=<uid> APP_GID=<gid> 對齊宿主帳號
ARG APP_UID=1000
ARG APP_GID=1000
RUN groupadd -g ${APP_GID} app 2>/dev/null || true \
    && useradd -u ${APP_UID} -g ${APP_GID} -m -s /usr/sbin/nologin app 2>/dev/null || true \
    && mkdir -p /app/out /data /work \
    && chown -R ${APP_UID}:${APP_GID} /app/out /data /work
USER ${APP_UID}:${APP_GID}

# 輸入掛在 /data（唯讀），entrypoint 會先複製到 /work 再處理（ODL 暫存檔不碰原檔）。
# 輸出固定寫到 /app/out —— 不能用預設的 ./output，因為那是程式碼模組的目錄；
# 使用者傳 -o 會覆蓋（argparse 後者優先）
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["--help"]
