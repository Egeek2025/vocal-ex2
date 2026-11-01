#!/usr/bin/env bash
# 在 Mac 上直接下载两位老师的课程视频（1080p），放进应用要读的文件夹。
#
#   tools/course/mac.sh setup          # 一次：用 Homebrew 装 ffmpeg / python / node，建 venv
#   tools/course/mac.sh check          # 检查网络、代理和 B 站登录
#   tools/course/mac.sh stoney         # Justin Stoney：应用里用到的那些集（YouTube）
#   tools/course/mac.sh peo            # Peo 老师：18 个教学视频（Bilibili，用 Chrome 的登录拿 1080p）
#   tools/course/mac.sh all            # 两位老师都下载
#   tools/course/mac.sh upgrade        # 把以前的低分辨率视频重新下成 1080p
#   tools/course/mac.sh size           # 看看文件夹里有多少视频、占多大空间
#
# 设置（都可以不设）：
#   MEDIA=~/Movies/练声房视频          视频放在哪里（默认就是这个）；应用「设置」里选同一个文件夹
#   PROXY=http://127.0.0.1:7890       下载 YouTube 用的代理（Clash、V2Ray 等的本地 HTTP/SOCKS 端口）
#   BILI_PROXY=...                    下载 B 站用的代理；默认不走代理直连（B 站在国内直连最快）
#   BROWSER=chrome                    读取哪个浏览器的 B 站登录：chrome、safari、firefox、"chrome:Profile 1"
#
# 例：PROXY=http://127.0.0.1:7890 tools/course/mac.sh all
#
# 第一次读取 Chrome 登录时，macOS 会弹窗询问是否允许访问「Chrome Safe Storage」，选「允许」。
# 登录信息只在本机读取，不会保存或上传。下载的视频只供个人学习，不要分享或上传。
set -euo pipefail
cd "$(dirname "$0")/../.."          # repository root
PY=tools/course/.venv/bin/python
export VOCAL_MEDIA="${MEDIA:-$HOME/Movies/练声房视频}"
BROWSER="${BROWSER:-chrome}"

need_venv() {
  if [ ! -x "$PY" ]; then
    echo "还没有安装，先运行：tools/course/mac.sh setup"
    exit 1
  fi
}

yt_proxy_args() {
  if [ -n "${PROXY:-}" ]; then echo "--proxy $PROXY"; fi
}

bili_env() {
  # peo.sh reads PROXY / DIRECT; Bilibili goes direct unless BILI_PROXY is set
  if [ -n "${BILI_PROXY:-}" ]; then echo "PROXY=$BILI_PROXY"; else echo "DIRECT=1"; fi
}

case "${1:-help}" in
  setup)
    if ! command -v brew >/dev/null; then
      echo "需要先安装 Homebrew：https://brew.sh （把页面上的一行命令粘贴到「终端」运行）"
      exit 1
    fi
    pkgs=()
    command -v ffmpeg >/dev/null || pkgs+=(ffmpeg)
    command -v python3 >/dev/null && python3 -c "import venv, ensurepip" 2>/dev/null || pkgs+=(python)
    command -v node >/dev/null || command -v deno >/dev/null || pkgs+=(node)
    if [ ${#pkgs[@]} -gt 0 ]; then
      echo "用 Homebrew 安装：${pkgs[*]}"
      brew install "${pkgs[@]}"
    fi
    tools/course/setup.sh
    mkdir -p "$VOCAL_MEDIA"
    echo
    echo "视频会放在：$VOCAL_MEDIA"
    echo "接着运行：tools/course/mac.sh check"
    ;;

  check)
    need_venv
    echo "== YouTube（Justin Stoney）"
    if curl -sS -m 10 -o /dev/null ${PROXY:+-x "$PROXY"} https://www.youtube.com; then
      echo "能连上 YouTube${PROXY:+（通过代理 $PROXY）}"
    else
      echo "连不上 YouTube。设置代理再试，例如：PROXY=http://127.0.0.1:7890 tools/course/mac.sh check"
    fi
    echo
    echo "== Bilibili（Peo 老师）"
    env $(bili_env) BROWSER="$BROWSER" tools/course/peo.sh check
    ;;

  stoney)
    need_venv
    # shellcheck disable=SC2046
    "$PY" tools/course/fetch.py --teacher stoney --only-exercises $(yt_proxy_args) ${2:+$2}
    ;;

  peo)
    need_venv
    env $(bili_env) BROWSER="$BROWSER" tools/course/peo.sh download
    ;;

  all)
    "$0" stoney
    "$0" peo
    "$0" size
    ;;

  upgrade)
    need_venv
    # shellcheck disable=SC2046
    "$PY" tools/course/fetch.py --teacher stoney --only-exercises --upgrade $(yt_proxy_args)
    env $(bili_env) BROWSER="$BROWSER" tools/course/peo.sh download
    ;;

  size)
    n=$( { find "$VOCAL_MEDIA" -name '*.mp4' ! -name '*.converting.mp4' 2>/dev/null || true; } | wc -l | tr -d ' ')
    echo "$VOCAL_MEDIA：$n 个视频，$(du -sh "$VOCAL_MEDIA" 2>/dev/null | cut -f1)"
    echo "在应用「设置」里选择这个文件夹；以后新下载了视频，在设置里点「重新查找」。"
    ;;

  *)
    sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
    ;;
esac
