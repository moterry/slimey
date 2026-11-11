#!/bin/sh
# Claude Code hook: records this session's state for the Slimey desktop pet.
# Usage: hook.sh running|waiting|done|end   (hook JSON arrives on stdin)
state="$1"
dir="${SLIMEY_DIR:-$HOME/.slimey}/sessions"
# First session_id in the payload; restricted charset so it is safe as a file name.
id=$(grep -o '"session_id"[[:space:]]*:[[:space:]]*"[A-Za-z0-9_-]*"' | head -n 1 | sed 's/.*"\([A-Za-z0-9_-]*\)"$/\1/')
[ -n "$id" ] || exit 0
mkdir -p "$dir"
case "$state" in
    end) rm -f "$dir/$id" ;;
    running|waiting|done) printf '%s\n' "$state" > "$dir/.$id.tmp" && mv "$dir/.$id.tmp" "$dir/$id" ;;
esac
exit 0
