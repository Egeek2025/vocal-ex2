#!/usr/bin/env bash
# One-time setup on Ubuntu: system tools via apt, Python packages in a venv at tools/course/.venv.
set -euo pipefail
cd "$(dirname "$0")"

missing=()
command -v ffmpeg >/dev/null || missing+=(ffmpeg)
python3 -c "import venv, ensurepip" 2>/dev/null || missing+=(python3-venv)
if ! command -v deno >/dev/null && ! command -v node >/dev/null; then missing+=(nodejs); fi
if ((${#missing[@]})); then
  echo "需要安装系统软件：${missing[*]}"
  echo "运行：sudo apt update && sudo apt install -y ${missing[*]}"
  exit 1
fi

if [ ! -d .venv ]; then
  python3 -m venv .venv
fi
.venv/bin/python -m pip install --upgrade pip >/dev/null
.venv/bin/python -m pip install -r requirements.txt
echo
echo "准备好了。之后的命令都用 venv 里的 Python 运行，例如："
echo "  tools/course/.venv/bin/python tools/course/fetch.py --only-exercises"
echo "或者先激活 venv：source tools/course/.venv/bin/activate"
