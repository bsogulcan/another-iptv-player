#!/bin/zsh
# usage: watch2.sh <udid> <outdir> [display-uuid]
D=$1; O=$2; DISP=$3
while true; do
  for r in $O/req-*(N); do n=${r:t}; n=${n#req-}
    if [ -n "$DISP" ]; then xcrun simctl io $D screenshot --display=$DISP $O/$n.png >/dev/null 2>&1
    else xcrun simctl io $D screenshot $O/$n.png >/dev/null 2>&1; fi
    rm -f $r; done
  sleep 0.3
done
