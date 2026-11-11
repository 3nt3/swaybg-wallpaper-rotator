#!/usr/bin/env bash
# Two-way, add-only sync between a local wallpaper dir and an Immich album.
#   1. up:   local images not in the album are uploaded and added to it
#   2. down: album images missing locally are downloaded
# Nothing is ever deleted on either side. Matching is by SHA-1 checksum.
#
# Config (env, e.g. from ~/.config/immich-wallpapers.env):
#   IMMICH_URL       e.g. https://immich.wg.3nt3.de
#   IMMICH_API_KEY   needs: album.read album.create albumAsset.create
#                           asset.read asset.upload asset.download
#   IMMICH_ALBUM     album name (default: Wallpapers)
#   WALLPAPER_DIR    default: ~/Pictures/wallpapers
set -euo pipefail

: "${IMMICH_URL:?IMMICH_URL not set}" "${IMMICH_API_KEY:?IMMICH_API_KEY not set}"
# Only one sync at a time (timer + manual run would download the same file twice).
exec 9> "${XDG_RUNTIME_DIR:-/tmp}/immich-wp-sync.lock"
flock -n 9 || { echo "another sync is running, skipping"; exit 0; }

ALBUM="${IMMICH_ALBUM:-Wallpapers}"
DIR="${WALLPAPER_DIR:-$HOME/Pictures/wallpapers}"

# Prefer a direct LAN URL when it answers (avoids hairpinning through the VPS).
# IMMICH_URL may be a space-separated list; the first that pings wins.
for u in $IMMICH_URL; do
  if curl -fsS -m 3 "${u%/}/api/server/ping" > /dev/null 2>&1; then API="${u%/}/api"; break; fi
done
: "${API:?no Immich URL reachable: $IMMICH_URL}"
echo "using $API"

api() { # api METHOD PATH [curl args...]
  local m=$1 p=$2; shift 2
  curl -fsS -X "$m" -H "x-api-key: $IMMICH_API_KEY" -H 'Accept: application/json' "$@" "$API$p"
}

b64sha1() { sha1sum "$1" | cut -d' ' -f1 | xxd -r -p | base64; }

mkdir -p "$DIR"
TMP=$(mktemp -d "$(dirname "$DIR")/.immich-wp-sync.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# --- album ---------------------------------------------------------------
album_id=$(api GET /albums | jq -r --arg n "$ALBUM" 'map(select(.albumName == $n)) | .[0].id // empty')
if [[ -z $album_id ]]; then
  album_id=$(api POST /albums -H 'Content-Type: application/json' \
    -d "$(jq -n --arg n "$ALBUM" '{albumName: $n}')" | jq -r .id)
  echo "created album '$ALBUM' ($album_id)"
fi

# --- remote listing: "checksum<TAB>id<TAB>originalFileName" ----------------
: > "$TMP/remote"
cursor=null
while :; do
  body=$(jq -n --arg a "$album_id" --argjson c "$cursor" \
    '{albumIds: [$a], type: "IMAGE", size: 1000} + (if $c then {cursor: $c} else {} end)')
  page=$(api POST /search/metadata -H 'Content-Type: application/json' -d "$body")
  jq -r '.assets.items[] | [.checksum, .id, .originalFileName] | @tsv' <<<"$page" >> "$TMP/remote"
  cursor=$(jq -c '.assets.nextCursor // null' <<<"$page")
  [[ $cursor == null ]] && break
done

# --- local listing: "checksum<TAB>path" -------------------------------------
: > "$TMP/local"
while IFS= read -r -d '' f; do
  printf '%s\t%s\n' "$(b64sha1 "$f")" "$f" >> "$TMP/local"
done < <(find "$DIR" -maxdepth 1 -type f -iregex '.*\.\(jpe?g\|png\|webp\|avif\|heic\|tiff?\|bmp\)' -print0)

# --- up ------------------------------------------------------------------
up=0; ids=()
while IFS=$'\t' read -r sum f; do
  grep -qF "$sum"$'\t' "$TMP/remote" && continue
  mtime=$(date -u -d "@$(stat -c %Y "$f")" +%Y-%m-%dT%H:%M:%S.000Z)
  id=$(api POST /assets -F "assetData=@$f" -F "filename=$(basename "$f")" \
        -F "fileCreatedAt=$mtime" -F "fileModifiedAt=$mtime" | jq -r .id)
  ids+=("$id"); up=$((up + 1)); echo "up:   $(basename "$f")"
done < "$TMP/local"
if ((${#ids[@]})); then
  api PUT "/albums/$album_id/assets" -H 'Content-Type: application/json' \
    -d "$(printf '%s\n' "${ids[@]}" | jq -R . | jq -s '{ids: .}')" > /dev/null
fi

# --- down ----------------------------------------------------------------
down=0
while IFS=$'\t' read -r sum id name; do
  grep -qF "$sum"$'\t' "$TMP/local" && continue
  name=${name//\//_}
  dest="$DIR/$name"
  [[ -e $dest ]] && dest="$DIR/${name%.*}-${id:0:8}.${name##*.}"
  api GET "/assets/$id/original" -o "$TMP/dl"
  got=$(b64sha1 "$TMP/dl")
  if grep -qF "$got"$'\t' "$TMP/local"; then
    # served bytes differ from the reported checksum but we already have them
    echo "warn: asset $id ($name) reports checksum $sum but serves $got (already local), skipping" >&2
    continue
  fi
  printf '%s\t%s\n' "$got" "$dest" >> "$TMP/local"
  mv "$TMP/dl" "$dest"   # atomic: the rotator never sees a partial file
  down=$((down + 1)); echo "down: $(basename "$dest")"
done < "$TMP/remote"

echo "sync done: $up up, $down down ($(wc -l < "$TMP/local") local, $(wc -l < "$TMP/remote") in album)"
