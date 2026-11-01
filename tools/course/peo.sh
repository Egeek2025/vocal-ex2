#!/usr/bin/env bash
# Peo 老师（Bilibili）：安装、获取视频列表、用 Chrome 的登录状态下载 1080p、转换格式、分析练习。
#
#   tools/course/peo.sh setup                 # 一次：装好 venv、yt-dlp 和读取 Chrome 登录需要的组件
#   tools/course/peo.sh check                 # 检查能不能用 Chrome 的登录拿到 1080p
#   tools/course/peo.sh list                  # 列出她的全部视频 -> tools/course/output/peo_catalog.json
#   tools/course/peo.sh download              # 下载她的声乐教学视频（下面 LESSONS 里挑好的 18 个）
#   tools/course/peo.sh download "混声|高音"   # 改为下载标题匹配这些关键词的
#   tools/course/peo.sh ids BV1xx,BV1yy       # 下载指定的视频
#   tools/course/peo.sh analyze               # 找出视频里的练习 -> tools/course/output/peo_report.md
#   tools/course/peo.sh all                   # list + download + analyze
#
# 登录：先在 Chrome 里登录 bilibili.com。Chrome 用的不是默认账户时，在 chrome://version 看「个人资料路径」
# 最后一段，例如：BROWSER="chrome:Profile 1" tools/course/peo.sh download
# 用 Chromium：BROWSER=chromium。登录信息只在本机读取，用完即止，不会保存或上传。
#
# 连不上 api.bilibili.com（超时）时：
#   DIRECT=1 tools/course/peo.sh check     # 不走终端里设置的代理（为 YouTube 设的代理常常连不上 B 站）
#   IPV4=1   tools/course/peo.sh check     # 只用 IPv4（IPv6 线路不通时）
#   PROXY=http://127.0.0.1:7890 ...        # 指定一个能访问 B 站的代理
set -euo pipefail
cd "$(dirname "$0")/../.."          # repository root
PY=tools/course/.venv/bin/python
BROWSER="${BROWSER:-chrome}"

# network options shared by every yt-dlp call
NET=()
if [ -n "${PROXY:-}" ]; then NET+=(--proxy "$PROXY"); elif [ -n "${DIRECT:-}" ]; then NET+=(--proxy ""); fi
[ -n "${IPV4:-}" ] && NET+=(--ipv4)
if [ -n "${DIRECT:-}" ]; then unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY; fi
SAMPLE_URL="https://space.bilibili.com/3546774224505365/video"
# her teaching videos, picked from the catalog by title (2026-11): technique lessons that may contain
# exercises. Left out: the song cover, the face-reveal intro, the opinion piece on choosing teachers,
# and the two clips under a minute.
LESSONS=(
  BV18vNd6sE2A  # 8分钟喉咙开启全盛状态（开嗓）
  BV1Gpjd6XEFw  # 测出真实音域
  BV12drSBpEeU  # 找到你自己真实的声音
  BV1DHcszMExr  # 气息
  BV1pXFLzAE9V  # 喉位
  BV1r76jB7E4U  # 腔体
  BV1TyDZBKEmf  # 头声
  BV1Hnun6QEqp  # 真假声切换
  BV1wqHD6iExK  # 换声点
  BV1MewWzNELk  # 混声
  BV1tY8b6ME5V  # 弱混
  BV1XNew6jERm  # 强混
  BV1eSAczUEwQ  # 破音、挤卡
  BV1M5V46REwK  # 别再挤卡
  BV17E5e6FELf  # 咽音
  BV1pBxe6vEs9  # 四个坏习惯
  BV1MtMw63Ees  # 摇滚
  BV1wu9QBmEL7  # R&B 唱法
)

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
    ytnet=()
    if [ -n "${PROXY:-}" ]; then ytnet+=(--proxy "$PROXY"); elif [ -n "${DIRECT:-}" ]; then ytnet+=(--proxy ""); fi
    [ -n "${IPV4:-}" ] && ytnet+=(--force-ipv4)
    url=$("$PY" -m yt_dlp ${ytnet[@]+"${ytnet[@]}"} --cookies-from-browser "$BROWSER" --socket-timeout 20 --flat-playlist --playlist-items 1 --print url "$SAMPLE_URL" 2>/dev/null | head -1 || true)
    if [ -z "$url" ]; then
      echo "没有拿到视频列表。连接超时的话，试试 DIRECT=1（不走代理）或 IPV4=1；Chrome 账户不是默认的，用 BROWSER=\"chrome:Profile 1\"。"
      exit 1
    fi
    formats=$("$PY" -m yt_dlp ${ytnet[@]+"${ytnet[@]}"} --cookies-from-browser "$BROWSER" -F "$url" 2>&1 || true)
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
    "$PY" tools/course/fetch.py --teacher peo --list --cookies-from-browser "$BROWSER" ${NET[@]+"${NET[@]}"}
    ;;

  download)
    need_venv
    if [ -n "${2:-}" ]; then
      echo "下载标题匹配「$2」的视频（1080p，已下载的会跳过）"
      "$PY" tools/course/fetch.py --teacher peo --match "$2" --cookies-from-browser "$BROWSER" ${NET[@]+"${NET[@]}"}
    else
      echo "下载 ${#LESSONS[@]} 个声乐教学视频（1080p，已下载的会跳过）"
      ids=$(IFS=,; echo "${LESSONS[*]}")
      "$PY" tools/course/fetch.py --teacher peo --ids "$ids" --cookies-from-browser "$BROWSER" ${NET[@]+"${NET[@]}"}
    fi
    ;;

  ids)
    need_venv
    [ -n "${2:-}" ] || { echo "用法：tools/course/peo.sh ids BV1xx,BV1yy"; exit 1; }
    "$PY" tools/course/fetch.py --teacher peo --ids "$2" --cookies-from-browser "$BROWSER" ${NET[@]+"${NET[@]}"}
    ;;

  analyze)
    need_venv
    "$PY" tools/course/discover.py --teacher peo
    echo
    echo "把 tools/course/output/peo_catalog.json 和 peo_report.md 发给 Claude（里面没有字幕原文）。"
    ;;

  all)
    "$0" list
    "$0" download ${2:+"$2"}
    "$0" analyze
    ;;

  *)
    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
    ;;
esac
