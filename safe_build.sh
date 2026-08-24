#!/bin/bash
# Memory-safe build wrapper for an 8 GB machine.
#
# The generated recomp translation units are enormous; a default-parallelism
# ninja run puts ~10 clang processes x 1-2 GB against 8 GB of RAM and wedges
# the whole Mac. This caps concurrency and, more importantly, watches free
# memory: the build is SIGSTOPped (not killed - work is preserved) whenever
# the system gets close to thrashing, and resumed once it recovers.
#
# usage: safe_build.sh <build-dir> [target] [jobs]
set -uo pipefail

BUILD_DIR="${1:?usage: safe_build.sh <build-dir> [target] [jobs]}"
TARGET="${2:-skate3}"
JOBS="${3:-3}"

# Emergency brake only. Idle sits near 1.6 GB free+inactive, so these are set
# well below that - the job cap is what keeps the build in budget day to day,
# and this exists to catch the link step or an unusually fat translation unit
# before the machine starts swapping.
LOW_MB=700
HIGH_MB=1300

page_size=$(sysctl -n hw.pagesize)

free_mb() {
  # "Free" for our purposes is free + inactive + speculative: pages the kernel
  # can hand out without swapping. Purely-free alone reads far too pessimistic
  # on macOS and would pause a healthy build.
  vm_stat | awk -v ps="$page_size" '
    /Pages free/                {f=$3}
    /Pages inactive/            {i=$3}
    /Pages speculative/         {s=$3}
    END {gsub(/\./,"",f); gsub(/\./,"",i); gsub(/\./,"",s);
         printf "%d", (f+i+s)*ps/1048576}'
}

echo "safe_build: dir=$BUILD_DIR target=$TARGET jobs=$JOBS (pause<${LOW_MB}MB, resume>${HIGH_MB}MB)"
echo "safe_build: free at start: $(free_mb) MB"

cmake --build "$BUILD_DIR" --target "$TARGET" -- -j "$JOBS" &
BUILD_PID=$!

paused=0
while kill -0 "$BUILD_PID" 2>/dev/null; do
  mb=$(free_mb)
  if [ "$paused" -eq 0 ] && [ "$mb" -lt "$LOW_MB" ]; then
    # Stop the whole process group so every in-flight clang halts, not just ninja.
    pkill -STOP -g $$ -f 'clang|ninja' 2>/dev/null
    kill -STOP "$BUILD_PID" 2>/dev/null
    paused=1
    echo "safe_build: PAUSED at ${mb}MB free"
  elif [ "$paused" -eq 1 ] && [ "$mb" -gt "$HIGH_MB" ]; then
    kill -CONT "$BUILD_PID" 2>/dev/null
    pkill -CONT -g $$ -f 'clang|ninja' 2>/dev/null
    paused=0
    echo "safe_build: RESUMED at ${mb}MB free"
  fi
  sleep 3
done

wait "$BUILD_PID"
rc=$?
echo "safe_build: exit=$rc free=$(free_mb) MB"
exit $rc
