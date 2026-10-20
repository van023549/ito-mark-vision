#!/usr/bin/env bash
# GitHub API 辅助脚本 —— 免 MCP，直接用 REST API
# 用法:
#   ./gh-api.sh me                          查账号信息
#   ./gh-api.sh repos                       列出仓库
#   ./gh-api.sh repo                        当前仓库信息
#   ./gh-api.sh files                       列出仓库文件
#   ./gh-api.sh issues                      列出 issue
#   ./gh-api.sh issue "标题" "内容"          建 issue
#   ./gh-api.sh pr                          列出 PR
#   ./gh-api.sh raw <path>                  原始 API 调用
#
# Token 从环境变量 GH_TOKEN 或同目录 .gh-token 读取

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOKEN_FILE="$SCRIPT_DIR/.gh-token"

if [ -z "${GH_TOKEN:-}" ] && [ -f "$TOKEN_FILE" ]; then
  GH_TOKEN="$(cat "$TOKEN_FILE")"
fi

if [ -z "${GH_TOKEN:-}" ]; then
  echo "错误: 未找到 token。请设置 GH_TOKEN 环境变量，或创建 $TOKEN_FILE" >&2
  exit 1
fi

API="https://api.github.com"
REPO="van023549/ito-mark-vision"

gh_api() {
  curl -s --noproxy '*' --max-time 25 \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "User-Agent: WorkBuddy-ito-mark-vision" \
    "$@"
}

CMD="${1:-me}"
shift || true

case "$CMD" in
  me)
    gh_api "$API/user" | python -c "
import json,sys
d=json.load(sys.stdin)
print('登录名 :', d.get('login'))
print('用户ID :', d.get('id'))
print('邮箱   :', d.get('email'))
print('主页   :', d.get('html_url'))
print('公开库 :', d.get('public_repos'))
"
    ;;
  repos)
    gh_api "$API/user/repos?per_page=100&sort=updated" | python -c "
import json,sys
d=json.load(sys.stdin)
if isinstance(d,dict): print('错误:', d.get('message')); sys.exit(1)
print(f'共 {len(d)} 个仓库:')
for r in d:
    print(f\"  {r['name']:<28} {r['visibility']:<8} {r['html_url']}\")
"
    ;;
  repo)
    gh_api "$API/repos/$REPO" | python -c "
import json,sys
d=json.load(sys.stdin)
print('名称     :', d['full_name'])
print('描述     :', d.get('description'))
print('默认分支 :', d['default_branch'])
print('star/fork:', d['stargazers_count'], '/', d['forks_count'])
print('open issue:', d['open_issues_count'])
print('主页     :', d['html_url'])
"
    ;;
  files)
    gh_api "$API/repos/$REPO/contents/${1:-}" | python -c "
import json,sys
d=json.load(sys.stdin)
if isinstance(d,dict): print('错误:', d.get('message')); sys.exit(1)
for f in d:
    kind = 'DIR ' if f['type']=='dir' else 'FILE'
    print(f\"  [{kind}] {f['name']:<30} {f.get('size',0):>8} bytes\")
"
    ;;
  issues)
    gh_api "$API/repos/$REPO/issues?state=open&per_page=50" | python -c "
import json,sys
d=json.load(sys.stdin)
if isinstance(d,dict): print('错误:', d.get('message')); sys.exit(1)
open_issues=[i for i in d if 'pull_request' not in i]
print(f'共 {len(open_issues)} 个开放 issue:')
for i in open_issues:
    labels = ','.join(l['name'] for l in i.get('labels',[]))
    print(f\"  #{i['number']:<4} {i['title']:<40} [{labels}] {i['html_url']}\")
"
    ;;
  issue)
    TITLE="${1:?用法: gh-api.sh issue \"标题\" \"内容\"}"
    BODY="${2:-}"
    gh_api -X POST "$API/repos/$REPO/issues" \
      -d "$(python -c "
import json,sys
print(json.dumps({'title': sys.argv[1], 'body': sys.argv[2]}))
" "$TITLE" "$BODY")" | python -c "
import json,sys
d=json.load(sys.stdin)
if d.get('number'):
    print(f\"✅ Issue #{d['number']} 已创建\")
    print('   ', d['html_url'])
else:
    print('错误:', json.dumps(d, ensure_ascii=False)[:300])
"
    ;;
  pr)
    gh_api "$API/repos/$REPO/pulls?state=open&per_page=50" | python -c "
import json,sys
d=json.load(sys.stdin)
if isinstance(d,dict): print('错误:', d.get('message')); sys.exit(1)
print(f'共 {len(d)} 个开放 PR:')
for p in d:
    print(f\"  #{p['number']:<4} {p['title']:<40} {p['head']['ref']} -> {p['base']['ref']}\")
    print(f\"        {p['html_url']}\")
"
    ;;
  raw)
    gh_api "$API$1" | python -m json.tool 2>/dev/null || gh_api "$API$1"
    ;;
  *)
    echo "未知命令: $CMD" >&2
    echo "可用: me repos repo files issues issue pr raw" >&2
    exit 1
    ;;
esac
