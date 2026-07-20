#!/usr/bin/env bash
set -euo pipefail

TEAM_ID_ONLY=0

usage() {
  cat <<'EOF'
Usage: ./find_xcode_teams.sh [--team-id-only]

List Apple Developer Team IDs available from the local codesigning keychain and
Xcode-managed provisioning profiles. The script is read-only.

Options:
  --team-id-only  Print unique Team IDs only, one per line.
  -h, --help      Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --team-id-only)
      TEAM_ID_ONLY=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must be run on macOS." >&2
  exit 1
fi

for command_name in security xcode-select xcodebuild plutil; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command is missing: $command_name" >&2
    exit 1
  fi
done

PLIST_BUDDY=/usr/libexec/PlistBuddy
if [[ ! -x "$PLIST_BUDDY" ]]; then
  echo "Required command is missing: $PLIST_BUDDY" >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/musescore-xcode-teams.XXXXXX")"
TEAMS_FILE="$TEMP_DIR/teams.tsv"
IDENTITIES_FILE="$TEMP_DIR/identities.tsv"
PROFILES_FILE="$TEMP_DIR/profiles.tsv"
touch "$TEAMS_FILE" "$IDENTITIES_FILE" "$PROFILES_FILE"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

sanitize_field() {
  printf '%s' "$1" | tr '\t\r\n' '   '
}

identity_type() {
  case "$1" in
    Developer\ ID\ Application:*) printf '%s' 'Developer ID Application' ;;
    Apple\ Distribution:*) printf '%s' 'Apple Distribution' ;;
    3rd\ Party\ Mac\ Developer\ Application:*) printf '%s' 'Mac App Store Distribution' ;;
    Apple\ Development:*|Mac\ Developer:*|iPhone\ Developer:*) printf '%s' 'Apple Development' ;;
    *) printf '%s' 'Other codesigning identity' ;;
  esac
}

RECOMMENDED_IDENTITY=""
while IFS= read -r identity; do
  [[ -n "$identity" ]] || continue
  team_id="$(
    printf '%s\n' "$identity" \
      | sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p'
  )"
  [[ -n "$team_id" ]] || continue

  type="$(identity_type "$identity")"
  owner="${identity#*: }"
  owner="${owner% ($team_id)}"
  printf '%s\t%s\t%s\n' \
    "$team_id" "$(sanitize_field "$type")" "$(sanitize_field "$identity")" \
    >> "$IDENTITIES_FILE"
  printf '%s\t%s\t%s\n' \
    "$team_id" "$(sanitize_field "$owner")" 'codesigning certificate' \
    >> "$TEAMS_FILE"

  if [[ -z "$RECOMMENDED_IDENTITY" \
        && "$type" == 'Developer ID Application' ]]; then
    RECOMMENDED_IDENTITY="$identity"
  fi
done < <(
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/^[^\"]*"\(.*\)"$/\1/p'
)

decode_profile() {
  local profile_path="$1"
  local plist_path="$2"

  if security cms -D -i "$profile_path" > "$plist_path" 2>/dev/null \
      && plutil -lint "$plist_path" >/dev/null 2>&1; then
    return 0
  fi

  : > "$plist_path"
  if command -v openssl >/dev/null 2>&1 \
      && openssl smime -inform DER -verify -noverify \
        -in "$profile_path" > "$plist_path" 2>/dev/null \
      && plutil -lint "$plist_path" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

PROFILE_INDEX=0
for profiles_dir in \
  "$HOME/Library/MobileDevice/Provisioning Profiles" \
  "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
  [[ -d "$profiles_dir" ]] || continue

  while IFS= read -r -d '' profile_path; do
    PROFILE_INDEX=$((PROFILE_INDEX + 1))
    profile_plist="$TEMP_DIR/profile-$PROFILE_INDEX.plist"
    if ! decode_profile "$profile_path" "$profile_plist"; then
      continue
    fi

    team_id="$(
      "$PLIST_BUDDY" -c 'Print :TeamIdentifier:0' "$profile_plist" 2>/dev/null \
        || "$PLIST_BUDDY" \
          -c 'Print :Entitlements:com.apple.developer.team-identifier' \
          "$profile_plist" 2>/dev/null \
        || true
    )"
    [[ -n "$team_id" ]] || continue

    team_name="$(
      "$PLIST_BUDDY" -c 'Print :TeamName' "$profile_plist" 2>/dev/null \
        || true
    )"
    profile_name="$(
      "$PLIST_BUDDY" -c 'Print :Name' "$profile_plist" 2>/dev/null \
        || basename "$profile_path"
    )"
    expiration="$(
      "$PLIST_BUDDY" -c 'Print :ExpirationDate' "$profile_plist" 2>/dev/null \
        || true
    )"
    [[ -n "$team_name" ]] || team_name='Unknown team name'
    [[ -n "$expiration" ]] || expiration='Unknown expiration'

    printf '%s\t%s\t%s\n' \
      "$(sanitize_field "$team_id")" "$(sanitize_field "$team_name")" \
      'Xcode provisioning profile' >> "$TEAMS_FILE"
    printf '%s\t%s\t%s\t%s\n' \
      "$(sanitize_field "$team_id")" "$(sanitize_field "$team_name")" \
      "$(sanitize_field "$profile_name")" "$(sanitize_field "$expiration")" \
      >> "$PROFILES_FILE"
  done < <(
    find "$profiles_dir" -maxdepth 1 -type f \
      \( -name '*.mobileprovision' -o -name '*.provisionprofile' \) \
      -print0 2>/dev/null
  )
done

if [[ "$TEAM_ID_ONLY" == "1" ]]; then
  if [[ ! -s "$TEAMS_FILE" ]]; then
    exit 1
  fi
  cut -f 1 "$TEAMS_FILE" | LC_ALL=C sort -u
  exit 0
fi

DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
XCODE_VERSION="$(xcodebuild -version 2>/dev/null | paste -sd ' ' - || true)"
printf 'Xcode: %s\n' "${XCODE_VERSION:-Unknown}"
printf 'Developer directory: %s\n' "${DEVELOPER_DIR:-Unknown}"

printf '\nAvailable teams:\n'
if [[ -s "$TEAMS_FILE" ]]; then
  awk -F '\t' '
    !seen[$1]++ {
      printf "  %-12s  %s\n", $1, $2
    }
  ' "$TEAMS_FILE"
else
  printf '  None found. Sign in to Xcode and download a provisioning profile.\n'
fi

printf '\nValid codesigning identities:\n'
if [[ -s "$IDENTITIES_FILE" ]]; then
  while IFS=$'\t' read -r team_id type identity; do
    printf '  [%s] %s\n' "$team_id" "$type"
    printf '    %s\n' "$identity"
  done < "$IDENTITIES_FILE"
else
  printf '  None. A Team ID alone cannot sign the app or DMG.\n'
fi

printf '\nXcode provisioning profiles:\n'
if [[ -s "$PROFILES_FILE" ]]; then
  LC_ALL=C sort -u "$PROFILES_FILE" \
    | while IFS=$'\t' read -r team_id team_name profile_name expiration; do
        printf '  [%s] %s: %s (expires %s)\n' \
          "$team_id" "$team_name" "$profile_name" "$expiration"
      done
else
  printf '  None found or none could be decoded.\n'
fi

if [[ -n "$RECOMMENDED_IDENTITY" ]]; then
  printf '\nRecommended DMG signing command:\n  '
  printf './build_signed_dmg.sh --sign-identity %q\n' "$RECOMMENDED_IDENTITY"
else
  printf '\nNo Developer ID Application identity is currently available.\n'
  printf 'Create or download one in Xcode Settings > Accounts > Manage Certificates.\n'
fi

if [[ ! -s "$TEAMS_FILE" ]]; then
  exit 1
fi
