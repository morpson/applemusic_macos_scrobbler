#!/bin/bash

# Apple Music to Last.fm Scrobbler: Power-optimized and single-instance
# ---------------------------------------------------------------------
# - Exits cleanly if Apple Music is not running.
# - Exits if Music quits during runtime.
# - Uses a lockfile to prevent multiple background processes.
# - Logs all events for easy debugging.
# - (Further enhancement via launchd to auto-launch on Music start is recommended.)

# ===== CONFIGURATION =====
API_KEY=""      # Your Last.fm API key
API_SECRET=""   # Your Last.fm API shared secret
SESSION_KEY=""  # Your Last.fm session key

LOG_FILE="$HOME/Library/Logs/apple_music_lastfm_scrobbler.log"
CACHE_FILE="$HOME/.apple_music_lastfm_scrobbler_cache"
LOCK_FILE="/tmp/apple_music_lastfm_scrobbler.lock"
POLL_INTERVAL=30  # Seconds between checking for track changes (can be adjusted)
MIN_PLAY_TIME=30
DEBUG=false
USE_KEYCHAIN=false

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
    if command -v md5sum >/dev/null 2>&1; then
        # Linux systems with md5sum
        echo -n "$1" | md5sum | cut -d ' ' -f 1
    else
        # macOS uses md5 -q
        echo -n "$1" | md5 -q
    fi
}

urlencode() {
    local string="$1"
    # Use LC_CTYPE=C to ensure we're working with bytes not characters
    LC_CTYPE=C
    
    # Replace special characters with URL encoding
    # This sed approach is much faster than byte-by-byte processing
    echo -n "$string" | sed -e 's/[^a-zA-Z0-9.~_-]/\\&/g' | while read -n1 c; do
        if [[ "$c" =~ [a-zA-Z0-9.~_-] ]]; then
            printf "%c" "$c"
        else
            printf "%%%02X" "'$c"
        fi
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

check_api_response() {
    local response="$1"
    local action="$2"
    
    if echo "$response" | grep -q "status=\"ok\""; then
        return 0
    else
        local error_code=$(echo "$response" | grep -o "code=\"[0-9]*\"" | grep -o "[0-9]*")
        local error_message=$(echo "$response" | grep -o "<error[^>]*>.*</error>" | 
                             sed 's/<error[^>]*>\(.*\)<\/error>/\1/')
        
        case "$error_code" in
            4)
                log "ERROR" "❌ Authentication failed: Invalid API key"
                ;;
            9)
                log "ERROR" "❌ Authentication failed: Invalid session key"
                ;;
            11|16)
                log "ERROR" "❌ Service error: Last.fm service is temporarily unavailable"
                ;;
            13)
                log "ERROR" "❌ Authentication failed: Invalid method signature"
                ;;
            *)
                log "ERROR" "❌ $action failed: $error_message (code: $error_code)"
                ;;
        esac
        return 1
    fi
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
    if check_api_response "$response" "Scrobble"; then
        log "INFO" "✅ Scrobbled: $artist - $track"
        echo "$artist - $track - $timestamp" >> "$CACHE_FILE"
        return 0
    else
        return 1
    fi
}

try_scrobble() {
    local artist="$1"
    local title="$2"
    local timestamp="$3"
    local album="$4"
    local duration="$5"
    local elapsed="$6"
    local threshold="$7"
    
    if [[ -z "$artist" || -z "$title" ]]; then
        return 1
    fi
    
    # Check if track has played long enough
    if (( elapsed >= threshold && elapsed >= MIN_PLAY_TIME )); then
        if should_scrobble "$artist" "$title" "$timestamp"; then
            scrobble_track "$artist" "$title" "$timestamp" "$album" "$duration" && return 0
        fi
    else
        log "DEBUG" "Not scrobbling: $elapsed s < $threshold s"
    fi
    
    return 1
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
    rm -f "$LOCK_FILE"
    exit 0
}

load_credentials_from_keychain() {
    log "INFO" "Attempting to load credentials from macOS Keychain..."
    
    # Try to load credentials from keychain
    API_KEY=$(security find-generic-password -a "lastfm_api_key" -s "com.user.applemusic_lastfm_scrobbler" -w 2>/dev/null)
    API_SECRET=$(security find-generic-password -a "lastfm_api_secret" -s "com.user.applemusic_lastfm_scrobbler" -w 2>/dev/null)
    SESSION_KEY=$(security find-generic-password -a "lastfm_session_key" -s "com.user.applemusic_lastfm_scrobbler" -w 2>/dev/null)
    
    if [[ -z "$API_KEY" || -z "$API_SECRET" || -z "$SESSION_KEY" ]]; then
        log "ERROR" "Failed to load credentials from keychain"
        return 1
    fi
    
    log "INFO" "Successfully loaded credentials from keychain"
    return 0
}

# ===== MAIN =====

# === Lockfile: only one instance allowed ===
if [ -f "$LOCK_FILE" ]; then
    OTHERPID=$(cat "$LOCK_FILE")
    if [ -d "/proc/$OTHERPID" ] 2>/dev/null || ps -p "$OTHERPID" &>/dev/null; then
        log "ERROR" "Another instance ($OTHERPID) already running. Exiting."
        exit 1
    else
        log "WARNING" "Stale lock file found. Removing."
        rm -f "$LOCK_FILE"
    fi
fi
echo $$ > "$LOCK_FILE"
trap cleanup SIGINT SIGTERM EXIT

touch "$LOG_FILE" "$CACHE_FILE"
tail -n 1000 "$CACHE_FILE" > "${CACHE_FILE}.tmp" && mv "${CACHE_FILE}.tmp" "$CACHE_FILE"

LAST_TITLE="" LAST_ARTIST="" LAST_ALBUM="" LAST_DURATION=0
TRACK_START_TIME=0 TRACK_TIMESTAMP=0 SCROBBLED=false

log "INFO" "🎵 Apple Music Last.fm scrobbler started"
if [[ "$USE_KEYCHAIN" == "true" ]]; then
    load_credentials_from_keychain || log "WARNING" "Failed to load from keychain, will use credentials from script"
fi
[[ -z "$API_KEY" || -z "$API_SECRET" || -z "$SESSION_KEY" ]] && log "ERROR" "API credentials missing" && cleanup

# ===== INITIAL CHECK: Exit if Music is not running =====
if ! is_music_running; then
    log "INFO" "Apple Music is not running. Exiting scrobbler."
    cleanup
fi

while true; do
    if get_current_track; then
        NOW=$(date +%s)
        if [[ "$CURRENT_TITLE" != "$LAST_TITLE" || "$CURRENT_ARTIST" != "$LAST_ARTIST" ]]; then
            if [[ "$SCROBBLED" == "false" && -n "$LAST_TITLE" ]]; then
                ELAPSED=$((NOW - TRACK_START_TIME))
                THRESHOLD=$((${LAST_DURATION%.*} / 2))
                (( THRESHOLD > 240 )) && THRESHOLD=240

                try_scrobble "$LAST_ARTIST" "$LAST_TITLE" "$TRACK_TIMESTAMP" "$LAST_ALBUM" "$LAST_DURATION" "$ELAPSED" "$THRESHOLD" && SCROBBLED=true
            fi

            LAST_TITLE="$CURRENT_TITLE"
            LAST_ARTIST="$CURRENT_ARTIST"
            LAST_ALBUM="$CURRENT_ALBUM"
            LAST_DURATION=${CURRENT_DURATION%.*}
            TRACK_START_TIME=$NOW
            TRACK_TIMESTAMP=$NOW
            SCROBBLED=false

            log "INFO" "Now playing: $CURRENT_ARTIST - $CURRENT_TITLE"
        elif [[ "$SCROBBLED" == "false" ]]; then
            ELAPSED=$((NOW - TRACK_START_TIME))
            THRESHOLD=$((${CURRENT_DURATION%.*} / 2))
            (( THRESHOLD > 240 )) && THRESHOLD=240
            
            try_scrobble "$CURRENT_ARTIST" "$CURRENT_TITLE" "$TRACK_TIMESTAMP" "$CURRENT_ALBUM" "$CURRENT_DURATION" "$ELAPSED" "$THRESHOLD" && SCROBBLED=true
        fi
    else
        # If Music is quit, exit immediately and clean up.
        if ! is_music_running; then
            log "INFO" "Apple Music has closed or is not running. Exiting scrobbler."
            cleanup
        fi
        
        if [[ -n "$LAST_TITLE" && "$SCROBBLED" == "false" ]]; then
            NOW=$(date +%s)
            ELAPSED=$((NOW - TRACK_START_TIME))
            THRESHOLD=$((${LAST_DURATION%.*} / 2))
            (( THRESHOLD > 240 )) && THRESHOLD=240

            if ! try_scrobble "$LAST_ARTIST" "$LAST_TITLE" "$TRACK_TIMESTAMP" "$LAST_ALBUM" "$LAST_DURATION" "$ELAPSED" "$THRESHOLD"; then
                log "INFO" "Stopped: Not enough time played"
            else
                SCROBBLED=true
            fi

            LAST_TITLE="" LAST_ARTIST="" LAST_ALBUM="" SCROBBLED=false
        fi
    fi

    sleep "$POLL_INTERVAL"
done

# ===== NOTES FOR FURTHER ENHANCEMENT =====
# For best experience, configure the launchd .plist with keys:
#   <key>KeepAlive</key>
#   <dict>
#      <key>OtherJobEnabled</key>
#      <key>PathState</key>
#      <dict>
#         <key>/Applications/Music.app</key>
#         <true/>
#      </dict>
#   </dict>
# This will restart scrobbler only when Music.app is running!
