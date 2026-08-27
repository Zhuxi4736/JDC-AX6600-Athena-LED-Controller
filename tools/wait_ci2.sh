#!/usr/bin/env bash
# 轮询最新一次 run 的状态, 编完(成功/失败)立即退出并打印结论
REPO=Zhuxi4736/JDC-AX6600-Athena-LED-Controller
API=https://api.github.com/repos/$REPO/actions/runs?per_page=1

echo "等待最新 CI run 完成..."
for i in $(seq 1 40); do
  json=$(curl -s "$API")
  # 用 python 取最新 run 的 status/conclusion/head_sha
  out=$(echo "$json" | python3 -c "
import sys,json
d=json.load(sys.stdin)
r=d['workflow_runs'][0]
print(r['head_sha'][:7], r['status'], r['conclusion'], r['html_url'])
" 2>/dev/null)
  sha=$(echo "$out" | awk '{print $1}')
  st=$(echo "$out" | awk '{print $2}')
  conc=$(echo "$out" | awk '{print $3}')
  url=$(echo "$out" | awk '{print $4}')
  echo "[$(date +%H:%M:%S)] sha=$sha status=$st conclusion=$conc"
  if [ "$st" = "completed" ]; then
    echo "=== DONE ==="
    echo "conclusion: $conc"
    echo "url: $url"
    if [ "$conc" = "success" ]; then
      echo "[OK] 编译通过, 抓 artifact:"
      rid=$(echo "$json" | python3 -c "import sys,json;print(json.load(sys.stdin)['workflow_runs'][0]['id'])" 2>/dev/null)
      curl -s "https://api.github.com/repos/$REPO/actions/runs/$rid/artifacts" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for a in d.get('artifacts',[]):
    print('  ART:',a['name'],'| id=',a['id'])
    print('  下载: https://github.com/$REPO/actions/runs/'$rid'/artifacts/'$a['id'])
"
    fi
    break
  fi
  sleep 30
done
