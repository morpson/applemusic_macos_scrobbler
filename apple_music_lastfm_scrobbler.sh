#!/bin/bash

# Apple Music to Last.fm Scrobbler
# ---------------------------------
# See full instructions at the end of this file

# ===== CONFIGURATION =====
API_KEY=""      # Your Last.fm API key
API_SECRET=""   # Your Last.fm API shared secret
SESSION_KEY=""  # Your Last.fm session key

LOG_FILE="$HOME/Library/Logs/apple_music_lastfm_scrobbler.log"
CACHE_FILE="$HOME/.apple_music_lastfm_scrobbler_cache"
POLL_INTERVAL=10
MIN_PLAY_TIME=30
DEBUG=false

# ===== UTILITIES =====
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    if [[ "$level" == "DEBUG" && "$DEBUG" != "true" ]]; then return; fi
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    if [ -t 1 ]; then echo "[$timestamp] [$level] $message"; fi
}

md5() {
    echo -n "$1" | md5sum | cut -d ' ' -f 1
}

urlencode() {
    local length=${#1}
    for (( i = 0; i < length; i++ )); do
        c="${1:$i:1}"
        [[ "$c" =~ [a-zA-Z0-9.~_-] ]] && printf "$c" || printf '%%%02X' "'$c"
    done
    echo
}

create_signature() {
    local params="$1"
    local string=""
    IFS=$'\n' sorted=($(sort <<< "$params"))
    unset IFS
    for param in "${sorted[@]}"; do string+="${param}"; done
    string+="${API_SECRET}"
    md5 "$string"
}

scrobble_track() {
    local artist="$1" track="$2" timestamp="$3" album="$4" duration="$5"
    local method="track.scrobble"

    log "INFO" "Scrobbling: $artist - $track ($album) @ $timestamp"

    local post_data=""
    local artist_enc=$(urlencode "$artist")
    local track_enc=$(urlencode "$track")
    local album_enc=$(urlencode "$album")
    local duration_enc=$(urlencode "$duration")
    local timestamp_enc=$(urlencode "$timestamp")

    local params="api_key${API_KEY}
artist${artist}
method${method}
sk${SESSION_KEY}
timestamp${timestamp}
track${track}"
    [[ -n "$album" ]] && params+="
album${album}"
    [[ -n "$duration" ]] && params+="
duration${duration}"

    local signature=$(create_signature "$params")

    post_data="method=$method&api_key=$API_KEY&artist=$artist_enc&track=$track_enc&timestamp=$timestamp_enc&api_sig=$signature&sk=$SESSION_KEY"
    [[ -n "$album" ]] && post_data+="&album=$album_enc"
    [[ -n "$duration" ]] && post_data+="&duration=$duration_enc"

    local response=$(curl -s -d "$post_data" "https://ws.audioscrobbler.com/2.0/")
    if echo "$response" | grep -q "status=\"ok\""; then
        log "INFO" "✅ Scrobbled: $artist - $track"
        echo "$artist - $track - $timestamp" >> "$CACHE_FILE"
        return 0
    else
        log "ERROR" "❌ Scrobble failed: $response"
        return 1
    fi
}

is_music_running() {
    pgrep -q "Music"
}

get_current_track() {
    if ! is_music_running; then
        log "DEBUG" "Music not running"
        return 1
    fi

    local info=$(osascript -e '
    tell application "Music"
        if it is running and player state is playing then
            set trackName to name of current track
            set artistName to artist of current track
            set albumName to album of current track
            set trackDuration to duration of current track
            set trackPosition to player position
            return trackName & "|" & artistName & "|" & albumName & "|" & trackDuration & "|" & trackPosition
        end if
    end tell')

    [[ -z "$info" ]] && return 1
    IFS='|' read -r CURRENT_TITLE CURRENT_ARTIST CURRENT_ALBUM CURRENT_DURATION CURRENT_POSITION <<< "$info"

    log "DEBUG" "Track: $CURRENT_ARTIST - $CURRENT_TITLE ($CURRENT_POSITION/$CURRENT_DURATION)"
    return 0
}

should_scrobble() {
    [[ -z "$1" || -z "$2" ]] && return 1
    grep -q "$1 - $2 - $3" "$CACHE_FILE" && return 1
    return 0
}

cleanup() {
    log "INFO" "Scrobbler shutting down"
    exit 0
}

# ===== MAIN =====
trap cleanup SIGINT SIGTERM
touch "$LOG_FILE" "$CACHE_FILE"
tail -n 1000 "$CACHE_FILE" > "${CACHE_FILE}.tmp" && mv "${CACHE_FILE}.tmp" "$CACHE_FILE"

LAST_TITLE="" LAST_ARTIST="" LAST_ALBUM="" LAST_DURATION=0
TRACK_START_TIME=0 TRACK_TIMESTAMP=0 SCROBBLED=false

log "INFO" "🎵 Apple Music Last.fm scrobbler started"
[[ -z "$API_KEY" || -z "$API_SECRET" || -z "$SESSION_KEY" ]] && log "ERROR" "API credentials missing" && exit 1

while true; do
    if get_current_track; then
        NOW=$(date +%s)
        if [[ "$CURRENT_TITLE" != "$LAST_TITLE" || "$CURRENT_ARTIST" != "$LAST_ARTIST" ]]; then
            if [[ "$SCROBBLED" == "false" && -n "$LAST_TITLE" ]]; then
                ELAPSED=$((NOW - TRACK_START_TIME))
                THRESHOLD=$((LAST_DURATION / 2))
                (( THRESHOLD > 240 )) && THRESHOLD=240

                if (( ELAPSED >= THRESHOLD && ELAPSED >= MIN_PLAY_TIME )); then
                    if should_scrobble "$LAST_ARTIST" "$LAST_TITLE" "$TRACK_TIMESTAMP"; then
                        scrobble_track "$LAST_ARTIST" "$LAST_TITLE" "$TRACK_TIMESTAMP" "$LAST_ALBUM" "$LAST_DURATION" && SCROBBLED=true
                    fi
                else
                    log "INFO" "Skipped: $ELAPSED s < $THRESHOLD s"
                fi
            fi

            LAST_TITLE="$CURRENT_TITLE"
            LAST_ARTIST="$CURRENT_ARTIST"
            LAST_ALBUM="$CURRENT_ALBUM"
            LAST_DURATION=$((CURRENT_DURATION))
            TRACK_START_TIME=$NOW
            TRACK_TIMESTAMP=$NOW
            SCROBBLED=false

            log "INFO" "Now playing: $CURRENT_ARTIST - $CURRENT_TITLE"
        elif [[ "$SCROBBLED" == "false" ]]; then
            ELAPSED=$((NOW - TRACK_START_TIME))
            THRESHOLD=$((CURRENT_DURATION / 2))
            (( THRESHOLD > 240 )) && THRESHOLD=240
            if (( ELAPSED >= THRESHOLD && ELAPSED >= MIN_PLAY_TIME )); then
                if should_scrobble "$CURRENT_ARTIST" "$CURRENT_TITLE" "$TRACK_TIMESTAMP"; then
                    scrobble_track "$CURRENT_ARTIST" "$CURRENT_TITLE" "$TRACK_TIMESTAMP" "$CURRENT_ALBUM" "$CURRENT_DURATION" && SCROBBLED=true
                fi
            else
                log "DEBUG" "Still playing: $ELAPSED/$THRESHOLD seconds"
            fi
        fi
    else
        if [[ -n "$LAST_TITLE" && "$SCROBBLED" == "false" ]]; then
            NOW=$(date +%s)
            ELAPSED=$((NOW - TRACK_START_TIME))
            THRESHOLD=$((LAST_DURATION / 2))
            (( THRESHOLD > 240 )) && THRESHOLD=240

            if (( ELAPSED >= THRESHOLD && ELAPSED >= MIN_PLAY_TIME )); then
                if should_scrobble "$LAST_ARTIST" "$LAST_TITLE" "$TRACK_TIMESTAMP"; then
                    scrobble_track "$LAST_ARTIST" "$LAST_TITLE" "$TRACK_TIMESTAMP" "$LAST_ALBUM" "$LAST_DURATION" && SCROBBLED=true
                fi
            else
                log "INFO" "Stopped: Not enough time played"
            fi

            LAST_TITLE="" LAST_ARTIST="" LAST_ALBUM="" SCROBBLED=false
        fi
    fi

    sleep "$POLL_INTERVAL"
done
