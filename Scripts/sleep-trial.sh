#!/usr/bin/env bash
# =============================================================================
# sleep-trial.sh — Measure what wakes a lid-shut Mac on battery
#
# Records the state before a trial (time, battery, Bluetooth, Wi-Fi) and, after
# the trial, reports the DarkWake count and reasons from `pmset -g log` since
# that start time, plus the battery drop.
#
# Usage:
#   ./Scripts/sleep-trial.sh start <label>    # run just before shutting the lid
#   ./Scripts/sleep-trial.sh report <label>   # run after waking the Mac
#
# Start files live in ~/Library/Application Support/Insomnia/sleep-trials/.
# =============================================================================
set -euo pipefail

TRIAL_DIR="$HOME/Library/Application Support/Insomnia/sleep-trials"
WIFI_DEVICE="${WIFI_DEVICE:-en0}"

usage() {
  echo "usage: $(basename "$0") start <label> | report <label>" >&2
  exit 2
}

# Labels become file names, so keep them to a safe character set.
validate_label() {
  if [[ ! "$1" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "error: label must match [A-Za-z0-9._-]+ (got '$1')" >&2
    exit 2
  fi
}

# Current battery percentage, or "unknown" on a desktop / unreadable output.
battery_percent() {
  local pct
  pct="$(pmset -g batt | grep -Eo '[0-9]+%' | head -1 | tr -d '%' || true)"
  echo "${pct:-unknown}"
}

# Bluetooth controller power as "on", "off" or "unknown".
bluetooth_power() {
  local state
  # system_profiler reports "State: On/Off" for the controller; it is the documented, non-private source.
  state="$(system_profiler SPBluetoothDataType 2>/dev/null | awk -F': ' '/^ *State:/ {print tolower($2); exit}' || true)"
  if [[ -z "$state" ]]; then
    # Fallback: the preference the Bluetooth stack persists (1 = on, 0 = off).
    local raw
    raw="$(defaults read /Library/Preferences/com.apple.Bluetooth ControllerPowerState 2>/dev/null || true)"
    case "$raw" in
      1) state="on" ;;
      0) state="off" ;;
      *) state="unknown" ;;
    esac
  fi
  echo "$state"
}

# Wi-Fi power as "on", "off" or "unknown".
wifi_power() {
  local out
  out="$(networksetup -getairportpower "$WIFI_DEVICE" 2>/dev/null || true)"
  case "$out" in
    *": On") echo "on" ;;
    *": Off") echo "off" ;;
    *) echo "unknown" ;;
  esac
}

# Prints the value for KEY from a key=value file (empty if absent).
read_key() {
  local line
  line="$(grep -m1 "^$2=" "$1" || true)"
  echo "${line#*=}"
}

cmd_start() {
  local label="$1"
  validate_label "$label"
  mkdir -p "$TRIAL_DIR"
  local file="$TRIAL_DIR/$label.start"
  {
    echo "start_epoch=$(date +%s)"
    echo "start_local=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "battery_percent=$(battery_percent)"
    echo "bluetooth=$(bluetooth_power)"
    echo "wifi=$(wifi_power)"
  } > "$file"
  echo "Recorded start for '$label':"
  sed 's/^/  /' "$file"
  echo "Shut the lid now."
}

cmd_report() {
  local label="$1"
  validate_label "$label"
  local file="$TRIAL_DIR/$label.start"
  if [[ ! -f "$file" ]]; then
    echo "error: no start file for '$label' (expected $file)" >&2
    exit 1
  fi
  # Parse key=value lines instead of sourcing: values such as the local time contain spaces.
  local start_epoch start_local battery_percent bluetooth wifi
  start_epoch="$(read_key "$file" start_epoch)"
  start_local="$(read_key "$file" start_local)"
  battery_percent="$(read_key "$file" battery_percent)"
  bluetooth="$(read_key "$file" bluetooth)"
  wifi="$(read_key "$file" wifi)"
  if [[ ! "$start_epoch" =~ ^[0-9]+$ ]]; then
    echo "error: start file $file is missing a valid start_epoch" >&2
    exit 1
  fi

  local now_epoch elapsed battery_now drop
  now_epoch="$(date +%s)"
  elapsed=$(( now_epoch - start_epoch ))
  battery_now="$(battery_percent)"
  if [[ "$battery_percent" =~ ^[0-9]+$ && "$battery_now" =~ ^[0-9]+$ ]]; then
    drop=$(( battery_percent - battery_now ))
  else
    drop="unknown"
  fi

  echo "Trial: $label"
  echo "Started:  $start_local  (bluetooth=$bluetooth, wifi=$wifi)"
  printf 'Elapsed:  %dh %02dm %02ds\n' $((elapsed / 3600)) $(((elapsed % 3600) / 60)) $((elapsed % 60))
  echo "Battery:  ${battery_percent}% -> ${battery_now}%  (drop: ${drop})"

  # pmset log lines start with "YYYY-MM-DD HH:MM:SS +ZZZZ". Convert each to epoch seconds (offset included)
  # so the comparison is correct across timezone and DST changes, instead of comparing local strings.
  local start_day="${start_local%% *}"
  local -a dark_lines=()
  local full_wake_epoch=""
  local line stamp epoch
  while IFS= read -r line; do
    stamp="${line:0:25}"
    epoch="$(date -j -f '%Y-%m-%d %H:%M:%S %z' "$stamp" +%s 2>/dev/null || true)"
    [[ "$epoch" =~ ^[0-9]+$ ]] || continue
    (( epoch >= start_epoch )) || continue
    if [[ "$line" =~ [[:space:]]DarkWake[[:space:]]+DarkWake[[:space:]]from ]]; then
      dark_lines+=("$line")
    elif [[ "$line" =~ [[:space:]]Wake[[:space:]]+(DarkWake[[:space:]]to[[:space:]]FullWake|Wake[[:space:]]from) ]]; then
      # The first full wake after the start ends the trial window; later activity is the user's.
      full_wake_epoch="$epoch"
      break
    fi
  done < <(pmset -g log | awk -v day="$start_day" 'substr($0,1,10) >= day && ($0 ~ / DarkWake[ \t]+DarkWake from / || $0 ~ / Wake[ \t]+(DarkWake to FullWake|Wake from)/)')

  local count="${#dark_lines[@]}"
  if [[ -n "$full_wake_epoch" ]]; then
    echo "Window:   start -> first full wake at $(date -r "$full_wake_epoch" '+%Y-%m-%d %H:%M:%S')"
  else
    echo "Window:   start -> now (no full wake logged yet)"
  fi
  echo "DarkWakes: $count"

  if (( count > 0 )); then
    # A battery trial that logs AC events was plugged in at some point, which invalidates it.
    local on_ac=0
    for line in "${dark_lines[@]}"; do
      [[ "$line" == *"Using AC"* ]] && on_ac=$((on_ac + 1))
    done
    if (( on_ac > 0 )); then
      echo "WARNING:  $on_ac of $count DarkWakes happened on AC power; this is not a clean battery trial."
    fi

    echo "Reasons (hex like 0x70070000 stripped):"
    # Keep the text after "due to", drop the "Using AC/Batt (Charge...)" tail, strip hex flags and the "()" they leave.
    printf '%s\n' "${dark_lines[@]}" \
      | sed -E 's/^.*due to[[:space:]]+//' \
      | sed -E 's/[[:space:]]+Using (AC|Batt|BATT).*$//' \
      | sed -E 's/0x[0-9a-fA-F]+//g; s/\(\)//g; s/\.[[:space:]]/ /g; s/[[:space:]]+/ /g; s/^ //; s/ $//' \
      | sort | uniq -c | sort -rn \
      | sed 's/^/  /'
  fi
}

[[ $# -eq 2 ]] || usage
case "$1" in
  start) cmd_start "$2" ;;
  report) cmd_report "$2" ;;
  *) usage ;;
esac
