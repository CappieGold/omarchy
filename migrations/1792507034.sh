echo "Check network connectivity against ping.omarchy.org"

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

# omarchy-settings ships the drop-in; NetworkManager only reads it on reload.
as_root nmcli general reload conf >/dev/null 2>&1 || true
