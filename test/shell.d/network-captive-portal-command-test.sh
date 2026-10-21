#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/bin"

# Every external effect is stubbed and logged: the real exit node, browser,
# NetworkManager and notifications are never touched.
stub() {
  printf '#!/bin/bash\n%s\n' "$2" > "$stage/bin/$1"
  chmod +x "$stage/bin/$1"
}
stub tailscale 'printf "%s\n" "$TEST_TAILSCALE_STATUS"'
stub curl 'printf "curl %s\n" "${@: -1}" >> "$TEST_LOG"; exit "${TEST_CURL_STATUS:-0}"'
stub omarchy-launch-browser 'printf "browser %s\n" "$*" >> "$TEST_LOG"'
stub omarchy-notification-send 'printf "notify %s\n" "$*" >> "$TEST_LOG"'
stub sleep ':'
# Reports a portal for the first two checks, then full connectivity.
stub nmcli 'count=$(( $(cat "$TEST_NMCLI_COUNT" 2>/dev/null || echo 0) + 1 )); echo "$count" > "$TEST_NMCLI_COUNT"; if (( count > 2 )); then echo full; else echo portal; fi'

run_portal() {
  rm -f "$stage/log" "$stage/count"
  TEST_LOG="$stage/log" TEST_NMCLI_COUNT="$stage/count" TEST_TAILSCALE_STATUS="$1" TEST_CURL_STATUS="${2:-0}" \
    PATH="$stage/bin:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-network-captive-portal" "http://ping.omarchy.org/nm-check.txt"
}

toggle="http://local-tailscaled.sock/localapi/v0/set-use-exit-node-enabled"

run_portal '{"ExitNodeStatus":{"ID":"node","Online":true}}'
expected="curl $toggle?enabled=false
notify Tailscale exit node paused It comes back once you're signed in
browser http://ping.omarchy.org/nm-check.txt
curl $toggle?enabled=true
notify Tailscale exit node restored"
[[ $(<"$stage/log") == "$expected" ]] || fail "pauses the exit node, opens the portal, and restores it once online" "$(<"$stage/log")"
pass "pauses the exit node, opens the portal, and restores it once online"
[[ $(<"$stage/count") == 3 ]] || fail "re-checks until connectivity is full, then stops" "$(<"$stage/count")"
pass "re-checks until connectivity is full, then stops"

run_portal '{"ExitNodeStatus":null}'
[[ $(<"$stage/log") == "browser http://ping.omarchy.org/nm-check.txt" ]] || fail "leaves Tailscale alone without an exit node" "$(<"$stage/log")"
pass "leaves Tailscale alone without an exit node"

run_portal '{"ExitNodeStatus":{"ID":"node","Online":true}}' 1
[[ $(<"$stage/log") == "curl $toggle?enabled=false
browser http://ping.omarchy.org/nm-check.txt" ]] || fail "does not restore an exit node it failed to pause" "$(<"$stage/log")"
pass "does not restore an exit node it failed to pause"
