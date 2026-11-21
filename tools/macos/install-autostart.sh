#!/bin/sh
# Run once per OS user, from that user's graphical login session.
set -eu
umask 077
if [ "$#" -ne 2 ] || [ ! -f "$1" ] || [ ! -x "$1" ] || [ ! -d "$2" ]; then
  echo "Usage: $0 <verified nexbot-engine binary> <bot profile directory>" >&2
  exit 2
fi
binary=$1
profile=$(cd "$2" && pwd -P)
label=cc.nexbot.engine
domain=gui/$(id -u)
install_dir="$HOME/Library/Application Support/nExBot"
agents="$HOME/Library/LaunchAgents"
plist="$agents/$label.plist"
service="$domain/$label"

mkdir -p "$install_dir" "$agents"
chmod 700 "$install_dir"
binary_tmp=$(mktemp "$install_dir/.engine.XXXXXX")
plist_tmp=$(mktemp "$agents/.$label.XXXXXX")
trap 'rm -f "$binary_tmp" "$plist_tmp"' EXIT
install -m 700 "$binary" "$binary_tmp"
"$binary_tmp" --version

# plutil encodes each argument literally, including paths with spaces or ampersands.
plutil -create xml1 "$plist_tmp"
plutil -insert Label -string "$label" "$plist_tmp"
plutil -insert ProgramArguments -array "$plist_tmp"
plutil -insert ProgramArguments.0 -string "$install_dir/nexbot-engine" "$plist_tmp"
plutil -insert ProgramArguments.1 -string serve "$plist_tmp"
plutil -insert ProgramArguments.2 -string "$profile" "$plist_tmp"
plutil -insert KeepAlive -bool YES "$plist_tmp"
plutil -insert ThrottleInterval -integer 5 "$plist_tmp"
plutil -lint "$plist_tmp"

if launchctl print "$service" >/dev/null 2>&1; then
  launchctl bootout "$service"
fi
mv -f "$binary_tmp" "$install_dir/nexbot-engine"
mv -f "$plist_tmp" "$plist"
launchctl enable "$service"
launchctl bootstrap "$domain" "$plist"

# A crash-loop can still appear in launchctl print. Require the process to own a listener.
attempt=0
while [ "$attempt" -lt 25 ]; do
  pid=$(launchctl print "$service" | awk '$1 == "pid" && $2 == "=" {print $3; exit}')
  if [ -n "$pid" ] && /usr/sbin/lsof -nP -a -p "$pid" -iTCP@127.0.0.1 -sTCP:LISTEN >/dev/null; then
    echo "nExBot engine started for this user (pid $pid)."
    exit 0
  fi
  sleep 0.2
  attempt=$((attempt + 1))
done
echo "The engine did not open its local listener. Inspect launchctl print $service." >&2
exit 1
