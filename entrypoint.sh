#!/bin/bash
# 把唯讀掛載的 /data 複製到容器內的 /work 再處理：
# ODL 會把暫存 .md 寫在輸入檔旁邊，寫在副本旁就不會動到使用者的原始檔，
# 輸入 mount 因此可以維持 :ro。副本隨容器退出一起消失。
set -e

cp -r /data/. /work/ 2>/dev/null || true

# 使用者的參數照舊寫 /data/xxx，這裡轉成 /work/xxx
# 只在整段路徑就是 /data、或以 /data/ 開頭時才改寫，
# 避免誤傷剛好以 /data 開頭的其他字串（如 /database.pdf）
args=()
for a in "$@"; do
    case "$a" in
        /data)   args+=("/work") ;;
        /data/*) args+=("/work${a#/data}") ;;
        *)       args+=("$a") ;;
    esac
done

exec python cleaner.py -o /app/out "${args[@]}"
