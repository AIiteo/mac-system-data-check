#!/bin/bash
#
# System Data check - see what is inside "System Data" on a Mac.
# Version 1.0 (2026-10-21). From https://hoardless.app/guides/see-inside-system-data-mac
#
# READ-ONLY. This script only measures. It never deletes, moves, renames or
# writes any file (not even a temp file), never asks for an admin password,
# and never changes a setting. Every command in it is a read: df, du, sysctl,
# sw_vers, getconf, xcode-select -p, tmutil listlocalsnapshots,
# diskutil apfs listSnapshots, mdutil -s, docker context inspect and
# docker system df (only for a local Docker), simctl list, simctl runtime list,
# ollama list.
# Read it before you run it.
#
# Usage:
#   curl -fsSLO https://hoardless.app/tools/system-data-check.sh
#   less system-data-check.sh          # read it first
#   bash system-data-check.sh
#
# Works with the /bin/bash 3.2 that ships with macOS, and when piped into bash.
# Takes a minute or two on a full disk. Folders macOS protects are skipped and
# counted; give Terminal Full Disk Access to include them.
#
# Sizes are decimal like Finder and Storage settings: 1 GB = 1,000,000,000 bytes.
# du counts APFS clones and sparse files by the blocks they hold, so a sum of
# folders can differ from the Data volume's used figure.

set -u

VERSION="1.0"
TAB=$(printf '\t')
NL='
'
SKIPPED=0
KB=0
MARK=""
DU_OUT=""
LAST_SKIPS=0
GUIDES="https://hoardless.app/guides"
START=$SECONDS
HOME_DIR=${HOME:-}

if [ -z "$HOME_DIR" ] || [ ! -d "$HOME_DIR" ]; then
  echo "HOME is not set; cannot find your home folder." >&2
  exit 1
fi

# ---------------------------------------------------------------- helpers

# Progress note on stderr, only when stderr is a terminal, so pasted output stays clean.
progress() {
  if [ -t 2 ]; then printf '\r\033[K  measuring %s ...' "$1" >&2; fi
}
progress_done() {
  if [ -t 2 ]; then printf '\r\033[K' >&2; fi
}

# Show a path with the home folder as ~.
pretty() {
  case "$1" in
    "$HOME_DIR") printf '~' ;;
    "$HOME_DIR"/*) printf '~%s' "${1#"$HOME_DIR"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# Reads du output (stdout and stderr merged) and prints one summary:
#   S <skipped>            folders du could not read
#   T <kib>                the folder itself
#   C <kib> <name> <mark>  each direct child; mark is * when part was unreadable
#   H <kib> <path> <mark>  each wanted path (hot, | separated, relative to top)
DU_AWK='
BEGIN {
  FS = "\t"
  nh = split(hot, H, "|")
  for (i = 1; i <= nh; i++) if (H[i] != "") want[top "/" H[i]] = 1
}
/^du: / {
  skips++
  p = $0; sub(/^du: /, "", p); sub(/: [^:]*$/, "", p)
  if (index(p, top "/") == 1) {
    c = substr(p, length(top) + 2); sub(/\/.*/, "", c); badc[c] = 1
    for (h in want) if (p == h || index(p, h "/") == 1) badh[h] = 1
  }
  next
}
/^[0-9]+\t/ {
  if ($2 == top) { total = $1; next }
  r = substr($2, length(top) + 2)
  if (index(r, "/") == 0) ck[r] = $1
  if ($2 in want) hk[$2] = $1
}
END {
  printf "S\t%d\n", skips
  if (total != "") printf "T\t%s\n", total
  for (c in ck) printf "C\t%s\t%s\t%s\n", ck[c], c, (c in badc) ? "*" : ""
  for (h in hk) printf "H\t%s\t%s\t%s\n", hk[h], h, (h in badh) ? "*" : ""
}'

# du_scan DEPTH FOLDER [HOT]: one read-only du walk into $DU_OUT; counts skips.
du_scan() {
  local n
  DU_OUT=$(du -xk -d "$1" "$2" 2>&1 </dev/null | awk -v top="$2" -v hot="${3:-}" "$DU_AWK")
  n=$(printf '%s\n' "$DU_OUT" | awk -F'\t' '$1 == "S" { print $2 + 0 }')
  SKIPPED=$((SKIPPED + ${n:-0}))
  LAST_SKIPS=${n:-0}
}

# size_of PATH: total in KiB into $KB (-1 when unreadable), * into $MARK when partial.
size_of() {
  du_scan 0 "$1"
  KB=$(printf '%s\n' "$DU_OUT" | awk -F'\t' '$1 == "T" { t = $2 } END { print (t == "") ? -1 : t }')
  MARK=""
  [ "$LAST_SKIPS" -gt 0 ] && MARK="*"
}

# children_of FOLDER: rows "kib<TAB>name<TAB><TAB>mark" for each direct child.
children_of() {
  du_scan 1 "$1"
  printf '%s\n' "$DU_OUT" | awk -F'\t' '$1 == "C" { print $2 "\t" $3 "\t\t" $4 }'
}

# KiB from du to a decimal size like Finder.
human() {
  awk -v k="$1" 'BEGIN {
    if (k < 0) { printf "no access"; exit }
    b = k * 1024
    if (b >= 1e9)      printf "%.1f GB", b / 1e9
    else if (b >= 1e6) printf "%.0f MB", b / 1e6
    else if (b >= 1e3) printf "%.0f KB", b / 1e3
    else               printf "0 KB"
  }'
}

# print_rows ROWS [MAX]: rows are "kib<TAB>label<TAB>note<TAB>mark", printed
# largest first with aligned columns.
print_rows() {
  local rows=$1 limit=${2:-1000}
  if [ -z "$rows" ]; then
    echo "  (nothing found)"
    return
  fi
  printf '%s\n' "$rows" | grep . | sort -t "$TAB" -k1,1nr | head -n "$limit" | awk -F'\t' '
    function fmt(k,  b) {
      if (k < 0) return "no access"
      b = k * 1024
      if (b >= 1e9) return sprintf("%.1f GB", b / 1e9)
      if (b >= 1e6) return sprintf("%.0f MB", b / 1e6)
      if (b >= 1e3) return sprintf("%.0f KB", b / 1e3)
      return "0 KB"
    }
    {
      n++; k[n] = $1; l[n] = $2; t[n] = $3; m[n] = $4
      if (length($2) > w) w = length($2)
      if ($4 != "") marked = 1
    }
    END {
      if (w > 56) w = 56
      w += 2
      for (i = 1; i <= n; i++) {
        lab = l[i]
        if (length(lab) > w - 2) lab = substr(lab, 1, w - 5) "..."
        if (m[i] != "") lab = lab " *"
        if (t[i] != "") printf "  %9s  %-" w "s  %s\n", fmt(k[i]), lab, t[i]
        else            printf "  %9s  %s\n", fmt(k[i]), lab
      }
      if (marked) print "  * some or all of it could not be read, so the real size may be larger."
    }'
}

# run_limited SECONDS COMMAND...: stdin closed, output captured, 124 on time out.
run_limited() {
  local secs=$1 pid w rc
  shift
  "$@" </dev/null 2>&1 &
  pid=$!
  ( sleep "$secs"; kill "$pid" ) >/dev/null 2>&1 &
  w=$!
  wait "$pid"
  rc=$?
  if kill -0 "$w" 2>/dev/null; then
    kill "$w"
    wait "$w"
  else
    rc=124
  fi
  # Killed by the watcher's TERM even if it had not exited yet: still a timeout.
  [ $rc -eq 143 ] && rc=124
  return $rc
} 2>/dev/null

section() {
  progress_done
  echo
  echo "== $1 =="
}

next_read() {
  echo "  Read next: $GUIDES/$1"
}

# ---------------------------------------------------------------- banner

echo "System Data check $VERSION (hoardless.app)"
echo "Read-only: this only measures sizes. Nothing is deleted, moved or written."
echo "Sizes are decimal GB like Finder (1 GB = 1,000,000,000 bytes)."
echo "macOS $(sw_vers -productVersion 2>/dev/null </dev/null), $(date '+%Y-%m-%d %H:%M')"

# ---------------------------------------------------------------- 1. data volume

section "1. Data volume (where System Data lives)"
df -k /System/Volumes/Data 2>/dev/null </dev/null | awk 'NR == 2 {
  s = $2 * 1024; u = $3 * 1024; a = $4 * 1024
  printf "  Used: %.1f GB   Free: %.1f GB   Disk: %.1f GB\n", u / 1e9, a / 1e9, s / 1e9
}'
echo "  Storage settings splits the Data volume into categories; System Data is what is left."
next_read "see-inside-system-data-mac"

# ---------------------------------------------------------------- 2. snapshots

section "2. APFS snapshots"
tm=$(tmutil listlocalsnapshots / 2>/dev/null </dev/null | grep -v '^Snapshots for' | grep -v '^[[:space:]]*$')
if [ -n "$tm" ]; then
  tmn=$(printf '%s\n' "$tm" | grep -c .)
  echo "  Time Machine local snapshots: $tmn"
  printf '%s\n' "$tm" | head -n 10 | sed 's/^/    /'
  if [ "$tmn" -gt 10 ]; then echo "    ... and $((tmn - 10)) more"; fi
else
  echo "  Time Machine local snapshots: 0"
fi

for vol in / /System/Volumes/Data; do
  ds=$(diskutil apfs listSnapshots "$vol" 2>/dev/null </dev/null | awk '
    /Name:/ { sub(/^[[:space:]]*Name:[[:space:]]*/, ""); name = $0 }
    /Purgeable:/ {
      shown = name
      if (length(shown) > 60) shown = substr(shown, 1, 57) "..."
      note = ""
      if (name ~ /^com\.apple\.os\.update-/) note = "  macOS update snapshot, leave it alone"
      printf "    %s (purgeable: %s)%s\n", shown, $2, note
    }')
  if [ -n "$ds" ]; then
    dn=$(printf '%s\n' "$ds" | grep -c .)
    echo "  All snapshots on $vol: $dn"
    printf '%s\n' "$ds" | head -n 12
    if [ "$dn" -gt 12 ]; then echo "    ... and $((dn - 12)) more"; fi
  else
    echo "  All snapshots on $vol: 0"
  fi
done
echo "  macOS does not report snapshot size to any Terminal command."
echo "  Disk Utility shows it: View > Show APFS Snapshots."
next_read "delete-time-machine-snapshots"

# ---------------------------------------------------------------- 3. swap and sleepimage

section "3. Swap and sleepimage"
sysctl -n vm.swapusage 2>/dev/null </dev/null | awk '{
  for (i = 1; i < NF; i++) {
    if ($i == "total") t = $(i + 2)
    if ($i == "used")  u = $(i + 2)
  }
  mt = (t ~ /G$/) ? 1073741824 : 1048576; mu = (u ~ /G$/) ? 1073741824 : 1048576
  sub(/[MG]$/, "", t); sub(/[MG]$/, "", u)
  printf "  Swap in use: %.1f GB of %.1f GB allocated (on the separate VM volume)\n", u * mu / 1e9, t * mt / 1e9
}'
if [ -e /private/var/vm/sleepimage ]; then
  size_of /private/var/vm/sleepimage
  echo "  sleepimage: $(human "$KB") (/private/var/vm/sleepimage, kept for safe sleep)"
fi
echo "  Swap shrinks after a restart; it is not something to delete by hand."
next_read "system-data-keeps-growing-mac"

# ---------------------------------------------------------------- 4 and 5. ~/Library (one walk)

# Places inside ~/Library that often hide tens of GB: path|what|guide, one per line.
HOT_LIST='Caches|app caches|clear-cache-mac
Containers/com.docker.docker|Docker disk image|docker-raw-mac
Developer/CoreSimulator/Devices|iOS simulators|delete-ios-simulators
Developer/Xcode/DerivedData|Xcode build data|clear-xcode-deriveddata
Developer/Xcode/iOS DeviceSupport|device symbols|delete-ios-simulators
Developer/Xcode/Archives|Xcode archives|clear-xcode-deriveddata
Application Support/MobileSync/Backup|iPhone backups|delete-iphone-backups-mac
Messages|Messages attachments|see-inside-system-data-mac
Mail|Mail downloads|see-inside-system-data-mac
CloudStorage|cloud sync folders|see-inside-system-data-mac
Group Containers/UBF8T346G9.Office|Outlook and Office|see-inside-system-data-mac
Containers/com.apple.mediaanalysisd|Photos analysis|system-data-keeps-growing-mac
Application Support/Adobe|Adobe app data|clear-cache-mac
Caches/Adobe|Adobe caches|clear-cache-mac'

lib="$HOME_DIR/Library"
librows=""
hotrows=""
libkb=""
if [ -d "$lib" ]; then
  hot=$(printf '%s\n' "$HOT_LIST" | awk -F'|' '{ printf "%s|", $1 }')
  progress "~/Library (the slowest part)"
  du_scan 3 "$lib" "$hot"
  progress_done
  libkb=$(printf '%s\n' "$DU_OUT" | awk -F'\t' '$1 == "T" { print $2 }')
  librows=$(printf '%s\n' "$DU_OUT" | awk -F'\t' '$1 == "C" { print $2 "\t~/Library/" $3 "\t\t" $4 }')
  oldifs=$IFS
  IFS=$NL
  set -f
  for entry in $HOT_LIST; do
    IFS=$oldifs
    rel=${entry%%|*}
    rest=${entry#*|}
    what=${rest%%|*}
    guide=${rest#*|}
    p="$lib/$rel"
    [ -e "$p" ] || continue
    line=$(printf '%s\n' "$DU_OUT" | awk -F'\t' -v p="$p" '$1 == "H" && $3 == p { print $2 "\t" $4; exit }')
    if [ -n "$line" ]; then
      kb=${line%%"$TAB"*}
      mk=${line#*"$TAB"}
    else
      kb=-1
      mk="*"
    fi
    note=$(printf '%-21s %s' "$what" "$guide")
    hotrows="$hotrows$kb$TAB$(pretty "$p")$TAB$note$TAB$mk$NL"
  done
  IFS=$oldifs
  set +f
fi
if [ -e "$HOME_DIR/.Trash" ]; then
  size_of "$HOME_DIR/.Trash"
  note=$(printf '%-21s %s' "Trash" "empty it in Finder")
  hotrows="$hotrows$KB$TAB~/.Trash$TAB$note$TAB$MARK$NL"
fi

section "4. Largest folders in ~/Library (top 15)"
print_rows "$librows" 15
if [ -n "$libkb" ]; then echo "  Total ~/Library: $(human "$libkb")"; fi
next_read "clear-cache-mac"

section "5. Places that often hide tens of GB"
print_rows "$hotrows"
echo "  Read next: $GUIDES/<name in the last column>"

# ---------------------------------------------------------------- 6. dotfolders

section "6. Hidden folders in your home (top 10)"
rows=""
for p in "$HOME_DIR"/.[!.]*; do
  [ -d "$p" ] || continue
  [ -L "$p" ] && continue
  case "$p" in "$HOME_DIR/.Trash") continue ;; esac
  progress "$(pretty "$p")"
  size_of "$p"
  rows="$rows$KB$TAB$(pretty "$p")$TAB$TAB$MARK$NL"
done
progress_done
print_rows "$rows" 10
echo "  Tool caches (npm, pip, Hugging Face, Ollama models) collect here."
next_read "node-modules-npm-cache-mac"
next_read "ollama-hugging-face-models-mac"

# ---------------------------------------------------------------- 7. system side

section "7. System folders stored on the Data volume"
rows=""
add_sys() {
  [ -e "$1" ] || return 0
  progress "$1"
  size_of "$1"
  rows="$rows$KB$TAB$(pretty "$1")$TAB$2$TAB$MARK$NL"
}
add_sys /System/Library/AssetsV2                "macOS downloaded assets"
add_sys /Library/Developer/CoreSimulator         "simulator runtimes"
add_sys "/Library/Application Support"           "shared app data"
add_sys /private/var/db/diagnostics              "system logs"
add_sys /opt/homebrew                            "Homebrew"
tmp=${TMPDIR:-}
[ -n "$tmp" ] || tmp=$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null </dev/null)
userfolders=""
if [ -n "$tmp" ]; then
  userfolders=$(dirname "${tmp%/}")
  case "$userfolders" in
    /var/folders/*|/private/var/folders/*) add_sys "$userfolders" "your temp files and caches" ;;
    *) userfolders="" ;;
  esac
fi
progress_done
print_rows "$rows"

if [ -d /System/Library/AssetsV2 ]; then
  echo
  echo "  Largest items in /System/Library/AssetsV2:"
  progress "/System/Library/AssetsV2"
  arows=$(children_of /System/Library/AssetsV2)
  progress_done
  print_rows "$arows" 8 | sed 's/^/  /'
fi
if [ -n "$userfolders" ]; then
  echo
  echo "  Inside your part of /private/var/folders (C caches, T temp, 0 app data):"
  progress "$userfolders"
  frows=$(children_of "$userfolders")
  progress_done
  print_rows "$frows" 5 | sed 's/^/  /'
fi
echo "  These paths start with /System or /Library but are stored on the Data volume."
next_read "see-inside-system-data-mac"

# ---------------------------------------------------------------- 8. spotlight

section "8. Spotlight indexing"
mdutil -s / 2>/dev/null </dev/null | sed -e 's/^[[:space:]]*/  /' -e 's/[[:space:]]*$//'
echo "  If System Data jumps by tens of GB and drops again, look for mds_stores"
echo "  writing a lot in Activity Monitor > Disk. A reindex frees nothing by itself."
next_read "system-data-keeps-growing-mac"

# ---------------------------------------------------------------- 9. developer tools

section "9. Developer tools (only the ones installed)"
anytool=0

dockerhost=""
if command -v docker >/dev/null 2>&1 && [ -z "${DOCKER_HOST:-}" ]; then
  dockerhost=$(run_limited 5 docker context inspect --format '{{.Endpoints.docker.Host}}' | head -1)
fi
if command -v docker >/dev/null 2>&1 && ! printf '%s' "$dockerhost" | grep -q '^unix://'; then
  anytool=1
  echo "  Docker: skipped (not a local Docker on this Mac, so it would need the network)."
elif command -v docker >/dev/null 2>&1; then
  anytool=1
  progress "docker system df"
  out=$(run_limited 20 docker system df)
  rc=$?
  progress_done
  if [ $rc -eq 0 ] && [ -n "$out" ]; then
    echo "  docker system df (RECLAIMABLE is what Docker could free):"
    printf '%s\n' "$out" | sed 's/^/    /'
  elif [ $rc -eq 124 ]; then
    echo "  Docker: no answer within 20 seconds, skipped."
  else
    echo "  Docker: installed but not running, skipped. Its disk image is in section 5."
  fi
  next_read "docker-raw-mac"
fi

# Run simctl straight from the active developer folder, never through the
# /usr/bin/xcrun shim, so a Mac without Xcode never sees an install prompt.
devdir=$(xcode-select -p 2>/dev/null </dev/null)
simctl=""
if [ -n "$devdir" ] && [ -x "$devdir/usr/bin/simctl" ]; then simctl="$devdir/usr/bin/simctl"; fi
if [ -n "$simctl" ]; then
  anytool=1
  progress "simctl list"
  out=$(run_limited 30 "$simctl" list devices unavailable)
  rc=$?
  progress_done
  if [ $rc -eq 0 ]; then
    un=$(printf '%s\n' "$out" | grep -cE '\([0-9A-F]{8}-[0-9A-F-]{27}\)')
    echo "  Simulators whose runtime is gone (unavailable): $un"
  else
    echo "  Simulators: simctl did not answer, skipped."
  fi
  progress "simctl runtime list"
  out=$(run_limited 30 "$simctl" runtime list)
  rc=$?
  progress_done
  total=$(printf '%s\n' "$out" | grep 'Total Disk Images' | sed 's/^[[:space:]]*//')
  if [ $rc -eq 0 ] && [ -n "$total" ]; then
    echo "  Simulator runtimes: $total (size as simctl prints it)"
  fi
  next_read "delete-ios-simulators"
fi

if command -v ollama >/dev/null 2>&1; then
  anytool=1
  progress "ollama list"
  out=$(run_limited 10 ollama list)
  rc=$?
  progress_done
  if [ $rc -eq 0 ] && [ -n "$out" ]; then
    echo "  ollama list:"
    printf '%s\n' "$out" | head -n 20 | sed -e 's/[[:space:]]*$//' -e 's/^/    /'
  elif [ $rc -eq 124 ]; then
    echo "  Ollama: no answer within 10 seconds, skipped."
  else
    echo "  Ollama: installed but not running, skipped. Models are in ~/.ollama (section 6)."
  fi
  next_read "ollama-hugging-face-models-mac"
fi

if [ $anytool -eq 0 ]; then
  echo "  No Docker, Xcode simulators or Ollama found."
fi

# ---------------------------------------------------------------- footer

section "Done"
echo "  Finished in $((SECONDS - START)) seconds."
if [ $SKIPPED -gt 0 ]; then
  echo "  $SKIPPED folders could not be read (macOS protects them) and were skipped,"
  echo "  so some sizes above are low. To include them, give Terminal Full Disk Access:"
  echo "  System Settings > Privacy & Security > Full Disk Access, then run this again."
else
  echo "  Every folder was readable."
fi
echo "  Why the numbers keep changing: $GUIDES/system-data-keeps-growing-mac"
echo
echo "Nothing was changed. Hoardless (https://hoardless.app) shows the same breakdown with every byte named."
