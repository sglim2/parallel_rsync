#!/bin/bash
set -e

# typical scenario:
#   A one-time copy of large amounts of data, split across multiple directories.

usage() {
    cat <<'EOF'
Usage:
  parallel_rsync.sh -s SRC_HOST -S SRC_BASE -D DST_BASE [-j JOBS] [-X DIRNAME1 [-X DIRNAME2] ....]

Options:
  -s SRC_HOST   Source host to rsync from
  -S SRC_BASE   Source base directory on SRC_HOST
  -D DST_BASE   Destination base directory on the local machine
  -j JOBS       Number of parallel jobs (default: 6)
  -X DIRNAME    Exclude a directory name from the work list
                May be specified multiple times
  -h            Show this help

Example:
  parallel_rsync.sh \
    -s 192.168.0.21 \
    -S /mnt/data \
    -D /mnt/data \
    -X exclude-dir1 \
    -X exclude-dir2 \
    -j 8
EOF
}

SRC_HOST=""
SRC_BASE=""
DST_BASE=""
JOBS=6
EXCLUDES=()

while getopts ":s:S:D:j:X:h" opt; do
    case "$opt" in
        s) SRC_HOST="$OPTARG" ;;
        S) SRC_BASE="$OPTARG" ;;
        D) DST_BASE="$OPTARG" ;;
        j) JOBS="$OPTARG" ;;
        X) EXCLUDES+=("$OPTARG") ;;
        h)
            usage
            exit 0
            ;;
        :)
            echo "ERROR: Option -$OPTARG requires an argument." >&2
            usage >&2
            exit 1
            ;;
        \?)
            echo "ERROR: Invalid option: -$OPTARG" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$SRC_HOST" || -z "$SRC_BASE" || -z "$DST_BASE" ]]; then
    echo "ERROR: -s, -S, and -D are required." >&2
    usage >&2
    exit 1
fi

if ! [[ "$JOBS" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: JOBS must be a positive integer." >&2
    exit 1
fi

LOGDIR="/tmp/parallel_rsync-$(date +%F_%H%M%S)"
mkdir -p "$LOGDIR" "$DST_BASE"

SSH_OPTS='-o BatchMode=yes -o StrictHostKeyChecking=accept-new'
RSYNC_OPTS='-aW --numeric-ids --partial --partial-dir=.rsync-partial --info=stats2,progress2'

# Build remote command to list candidate directories
REMOTE_CMD="cd '$SRC_BASE' && find . -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V"

mapfile -t WORKLIST < <(
    ssh $SSH_OPTS "$SRC_HOST" "$REMOTE_CMD"
)

if [[ "${#WORKLIST[@]}" -eq 0 ]]; then
    echo "ERROR: No subdirectories found at ${SRC_HOST}:${SRC_BASE}" >&2
    exit 1
fi

# Apply exclusions locally
if [[ "${#EXCLUDES[@]}" -gt 0 ]]; then
    FILTERED_WORKLIST=()
    for item in "${WORKLIST[@]}"; do
        skip=0
        for excluded in "${EXCLUDES[@]}"; do
            if [[ "$item" == "$excluded" ]]; then
                skip=1
                break
            fi
        done
        if [[ "$skip" -eq 0 ]]; then
            FILTERED_WORKLIST+=("$item")
        fi
    done
    WORKLIST=("${FILTERED_WORKLIST[@]}")
fi

if [[ "${#WORKLIST[@]}" -eq 0 ]]; then
    echo "ERROR: All directories were excluded; nothing to sync." >&2
    exit 1
fi

echo "Syncing ${#WORKLIST[@]} directories with ${JOBS} parallel jobs"
echo "Logs: $LOGDIR"

if [[ "${#EXCLUDES[@]}" -gt 0 ]]; then
    echo "Excluding: ${EXCLUDES[*]}"
fi

export SRC_HOST SRC_BASE DST_BASE LOGDIR SSH_OPTS RSYNC_OPTS

run_one() {
    local item="$1"
    local log="$LOGDIR/${item}.log"

    echo "[$(date +%F\ %T)] START ${item}" | tee -a "$log"
    rsync $RSYNC_OPTS -e "ssh $SSH_OPTS" \
        "${SRC_HOST}:${SRC_BASE}/${item}/" \
        "${DST_BASE}/${item}/" >>"$log" 2>&1
    echo "[$(date +%F\ %T)] DONE  ${item}" | tee -a "$log"
}
export -f run_one

printf "%s\n" "${WORKLIST[@]}" | xargs -I{} -P "$JOBS" bash -lc 'run_one "$@"' _ {}

echo "All done. Logs: $LOGDIR"

