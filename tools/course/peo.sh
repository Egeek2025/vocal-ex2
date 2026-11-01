#!/usr/bin/env bash
# Peo 老师（Bilibili）：安装、获取视频列表、用 Chrome 的登录状态下载 1080p、转换格式、分析练习。
#
#   tools/course/peo.sh setup                 # 一次：装好 venv、yt-dlp 和读取 Chrome 登录需要的组件
#   tools/course/peo.sh check                 # 检查能不能用 Chrome 的登录拿到 1080p
#   tools/course/peo.sh list                  # 列出她的全部视频 -> tools/course/output/peo_catalog.json
#   tools/course/peo.sh download              # 下载标题像练声课的视频（默认关键词见下）
#   tools/course/peo.sh download "混声|高音"   # 只下载标题匹配这些关键词的
#   tools/course/peo.sh ids BV1xx,BV1yy       # 下载指定的视频
#   tools/course/peo.sh analyze               # 找出视频里的练习 -> tools/course/output/peo_report.md
#   tools/course/peo.sh all                   # list + download + analyze
#
# 登录：先在 Chrome 里登录 bilibili.com。Chrome 用的不是默认账户时，在 chrome://version 看「个人资料路径」
# 最后一段，例如：BROWSER="chrome:Profile 1" tools/course/peo.sh download
# 用 Chromium：BROWSER=chromium。登录信息只在本机读取，用完即止，不会保存或上传。
set -euo pipefail
cd "$(dirname "$0")/../.."          # repository root
PY=tools/course/.venv/bin/python
BROWSER="${BROWSER:-chrome}"
MATCH_DEFAULT="练声|发声|音阶|练习|气息|呼吸|混声|高音|头声|真声|假声|换声|共鸣|咬字|颤音|转音|SLS|热身|开嗓"
SAMPLE_URL="https://space.bilibili.com/3546774224505365/video"

need_venv() {
  if [ ! -x "$PY" ]; then
    echo "还没有安装，先运行：tools/course/peo.sh setup"
    exit 1
  fi
}

case "${1:-help}" in
  setup)
    tools/course/setup.sh
    echo
    echo "接着运行：tools/course/peo.sh check"
    ;;

  check)
    need_venv
    echo "用 $BROWSER 的登录状态读取一个 Peo 老师的视频，看能拿到的最高分辨率…"
    # the newest video of the channel
    url=$("$PY" -m yt_dlp --cookies-from-browser "$BROWSER" --flat-playlist --playlist-items 1 --print url "$SAMPLE_URL" 2>/dev/null | head -1 || true)
    if [ -z "$url" ]; then
      echo "没有拿到视频列表。检查网络；或者 Chrome 账户不是默认的，用 BROWSER=\"chrome:Profile 1\" 再试。"
      exit 1
    fi
    formats=$("$PY" -m yt_dlp --cookies-from-browser "$BROWSER" -F "$url" 2>&1 || true)
    if echo "$formats" | grep -qiE "could not (find|decrypt)|failed to decrypt|keyring|cookie.*(error|locked)"; then
      echo "$formats" | grep -iE "cookie|keyring|decrypt" | head -5
      echo
      echo "读取 Chrome 登录失败。可以试试：完全退出 Chrome 再运行；在桌面终端里运行（不要用 SSH）；"
      echo "或者 BROWSER=\"chrome+gnomekeyring\"（KDE 桌面用 chrome+kwallet）。"
      exit 1
    fi
    best=$(echo "$formats" | grep -oE '[0-9]{3,4}x[0-9]{3,4}' | awk -Fx '{print $2}' | sort -n | tail -1)
    echo "这个视频能拿到的最高分辨率：${best:-未知}p（$url）"
    if [ -n "$best" ] && [ "$best" -ge 1080 ]; then
      echo "登录有效，可以下载 1080p。接着运行：tools/course/peo.sh list"
    else
      echo "没有 1080p：Chrome 里可能还没登录 B 站，或者读到的不是登录的那个账户（见脚本开头的 BROWSER 说明）。"
    fi
    ;;

  list)
    need_venv
    "$PY" tools/course/fetch.py --teacher peo --list --cookies-from-browser "$BROWSER"
    ;;

  download)
    need_venv
    match="${2:-$MATCH_DEFAULT}"
    echo "下载标题匹配「$match」的视频（1080p，已下载的会跳过）"
    "$PY" tools/course/fetch.py --teacher peo --match "$match" --cookies-from-browser "$BROWSER"
    ;;

  ids)
    need_venv
    [ -n "${2:-}" ] || { echo "用法：tools/course/peo.sh ids BV1xx,BV1yy"; exit 1; }
    "$PY" tools/course/fetch.py --teacher peo --ids "$2" --cookies-from-browser "$BROWSER"
    ;;

  analyze)
    need_venv
    "$PY" tools/course/discover.py --teacher peo
    echo
    echo "把 tools/course/output/peo_catalog.json 和 peo_report.md 发给 Claude（里面没有字幕原文）。"
    ;;

  all)
    "$0" list
    "$0" download "${2:-$MATCH_DEFAULT}"
    "$0" analyze
    ;;

  *)
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
    ;;
esac
