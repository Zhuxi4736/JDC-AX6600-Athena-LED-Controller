#!/usr/bin/env bash
REPO=Zhuxi4736/JDC-AX6600-Athena-LED-Controller
API=https://api.github.com/repos/$REPO/actions/runs?per_page=1
echo "等最新 run 编完, 抓 step summary 里的编译错误..."
for i in $(seq 1 40); do
  json=$(curl -s --max-time 20 "$API" -x http://127.0.0.1:31180 2>/dev/null || curl -s --max-time 20 "$API")
  sha=$(echo "$json" | python3 -c "import sys,json;print(json.load(sys.stdin)['workflow_runs'][0]['head_sha'][:7])" 2>/dev/null)
  st=$(echo "$json" | python3 -c "import sys,json;print(json.load(sys.stdin)['workflow_runs'][0]['status'])" 2>/dev/null)
  conc=$(echo "$json" | python3 -c "import sys,json;print(json.load(sys.stdin)['workflow_runs'][0]['conclusion'])" 2>/dev/null)
  rid=$(echo "$json" | python3 -c "import sys,json;print(json.load(sys.stdin)['workflow_runs'][0]['id'])" 2>/dev/null)
  echo "[$(date +%H:%M:%S)] sha=$sha status=$st conclusion=$conc"
  if [ "$st" = "completed" ]; then
    echo "=== 抓 job step summary ==="
    curl -s --max-time 20 "https://api.github.com/repos/$REPO/actions/runs/$rid/jobs" -x http://127.0.0.1:31180 2>/dev/null \
      | python3 -c "
import sys,json
d=json.load(sys.stdin)
for j in d.get('jobs',[]):
    for s in j.get('steps',[]):
        if 'summary' in s and s['summary']:
            print('### STEP', s['name'])
            print(s['summary'])
"
    break
  fi
  sleep 25
done
