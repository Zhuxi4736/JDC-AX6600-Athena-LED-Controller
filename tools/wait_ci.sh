#!/usr/bin/env bash
# 轮询 GitHub Actions run #16 (7195df6) 直到完成, 然后抓取 ipk artifact 下载链接
RUN_ID=33063391883
REPO=Zhuxi4736/JDC-AX6600-Athena-LED-Controller
API=https://api.github.com/repos/$REPO/actions/runs/$RUN_ID

echo "开始轮询 run #16 ($RUN_ID) ..."
for i in $(seq 1 40); do
  json=$(curl -s "$API")
  status=$(echo "$json" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('status'),d.get('conclusion'))" 2>/dev/null)
  echo "[$(date +%H:%M:%S)] status=$status"
  if echo "$status" | grep -q "completed"; then
    break
  fi
  sleep 30
done

echo "=== RUN 结束, 抓取 jobs 与 artifact 信息 ==="
curl -s "$API/jobs" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for j in d.get('jobs',[]):
    print('JOB:',j['name'],'| status=',j['status'],'| conclusion=',j['conclusion'])
"
echo "=== ARTIFACTS ==="
curl -s "$API/artifacts" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for a in d.get('artifacts',[]):
    print('ART:',a['name'],'| id=',a['id'],'| expired=',a.get('expired'))
    print('  download_url: https://github.com/'$REPO'/actions/runs/'$RUN_ID'/artifacts/'$a['id']'  (需在网页点下载, API 直链需 token)')
"
echo "=== 网页查看 ==="
echo "https://github.com/$REPO/actions/runs/$RUN_ID"
