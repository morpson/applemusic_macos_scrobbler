#!/bin/bash
#
# Apple Music to Last.fm Scrobbler
# -------------------------------

# ===== CONFIGURATION SECTION =====
API_KEY=""      # Your Last.fm API key
API_SECRET=""   # Your Last.fm API shared secret
SESSION_KEY=""  # Your session key

LOG_FILE="$HOME/Library/Logs/apple_music_lastfm_scrobbler.log"
CACHE_FILE="$HOME/.apple_music_lastfm_scrobbler_cache"
POLL_INTERVAL=10
MIN_PLAY_TIME=30
DEBUG=false

# ===== UTILITY FUNCTIONS =====

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    if [[ "$level" == "DEBUG" && "$DEBUG" != "true" ]]; then
        return
    fi

    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    if [ -t 1 ]; then echo "[$timestamp] [$level] $message"; fi
}

md5() {
    echo -n "$1" | md5sum | cut -d ' ' -f 1
}

urlencode() {
    local string="$1"
    local length="${#string}"
    local encoded=""
    
    for (( i = 0; i < length; i++ )); do
        local c="${string:$i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) encoded+="$c" ;;
            *) encoded+=$(printf '%%%02X' "'$c") ;;
        esac
    done

    echo "$encoded"
}

create_signature() {
    local params="$1"
    local string=""
    IFS=$'\n' sorted=($(sort <<< "$params"))
    unset IFS
    for param in "${sorted[@]}"; do
        string="${string}${param}"
    done
    string="${string}${API_SECRET}"
    md5 "$string"
}

scrobble_track() {
    local artist="$1"
    local track="$2"
    local timestamp="$3"
    local album="$4"
    local duration="$5"

    local method="track.scrobble"

    log "INFO" "Scrobbling track: $artist - $track ($album) with timestamp $timestamp"

    local artist_enc=$(urlencode "$artist")
    local track_enc=$(urlencode "$track")
    local album_enc=$(urlencode "$album")
    local timestamp_enc=$(urlencode "$timestamp")
    local duration_enc=$(urlencode "$duration")

    local params=""
    params+="api_key${API_KEY}"
    params+="artist${artist}"
    params+="method${method}"
    params+="sk${SESSION_KEY}"
    params+="timestamp${timestamp}"
    params+="track${track}"
    if [[ -n "$album" ]]; then params+="album${album}"; fi
    if [[ -n "$duration" ]]; then params+="duration${duration}"; fi

    local signature=$(create_signature "$params")

    local post_data="method=${method}&api_key=${API_KEY}&artist=${artist_enc}&track=${track_enc}&timestamp=${timestamp_enc}&api_sig=${signature}&sk=${SESSION_KEY}"
    if [[ -n "$album" ]]; then post_data+="&album=${album_enc}"; fi
    if [[ -n "$duration" ]]; then post_data+="&duration=${duration_enc}"; fi

    local response=$(curl -s -d "$post_data" "https://ws.audioscrobbler.com/2.0/")

    if echo "$response" | grep -q "status=\"ok\""; then
        log "INFO" "Successfully scrobbled: $artist - $track"
        echo "$artist - $track - $timestamp" >> "$CACHE_FILE"
        return 0
    else
        log "ERROR" "Failed to scrobble track: $response"
        return 1
    fi
}

is_music_running() {
    pgrep -q "Music"
    return $?
}

get_current_track() {
    if ! is_music_running; then
        log "DEBUG" "Apple Music is not running"
        return 1
    fi

    local track_info=$(osascript -e '
    tell application "Music"
        if it is running and player state is playing then
            set trackName to name of current track
            set artistName to artist of current track
            set albumName to album of current track
            set trackDuration to duration of current track
            set trackPosition to player position
            return trackName & "|" & artistName & "|" & albumName & "|" & trackDuration & "|" & trackPosition
        else
            return ""
        end if
    end tell
    ')

    if [[ -z "$track_info" ]]; then return 1; fi

    IFS='|' read -r title artist album duration position <<< "$track_info"
    CURRENT_TITLE="$title"
    CURRENT_ARTIST="$artist"
    CURRENT_ALBUM="$album"
    CURRENT_DURATION="$duration"
    CURRENT_POSITION="$position"

    log "DEBUG" "Track: $CURRENT_ARTIST - $CURRENT_TITLE ($CURRENT_ALBUM) Position: $CURRENT_POSITION/$CURRENT_DURATION"
    return 0
}

should_scrobble() {
    local artist="$1"
    local title="$2"
    local timestamp="$3"

    if [[ -z "$artist" || -z "$title" ]]; then return 1; fi

    if grep -q "$artist - $title - $timestamp" "$CACHE_FILE"; then
        log "DEBUG" "Track already scrobbled: $artist - $title"
        return 1
    fi

    return 0
}

cleanup() {
    log "INFO" "Shutting down scrobbler"
    exit 0
}

# ===== MAIN SCRIPT =====

trap cleanup SIGINT SIGTERM
touch "$LOG_FILE"
touch "$CACHE_FILE"
tail -n 1000 "$CACHE_FILE" > "${CACHE_FILE}.tmp" && mv "${CACHE_FILE}.tmp" "$CACHE_FILE"

LAST_TITLE=""
LAST_ARTIST=""
LAST_ALBUM=""
LAST_DURATION=""
TRACK_START_TIME=0
TRACK_TIMESTAMP=0
SCROBBLED=false

log "INFO" "Apple Music to Last.fm scrobbler started"

if [[ -z "$API_KEY" || -z "$API_SECRET" || -z "$SESSION_KEY" ]]; then
    log "ERROR" "Please set your Last.fm API credentials in the script"
    exit 1
fi

while true; do
    if get_current_track; then
        CURRENT_TIME=$(date +%s)

        if [[ "$CURRENT_TITLE" != "$LAST_TITLE" || "$CURRENT_ARTIST" != "$LAST_ARTIST" ]]; then
            log "INFO" "Track changed: $CURRENT_ARTIST - $CURRENT_TITLE"

            if [[ "$SCROBBLED" == "false" && -n "$LAST_TITLE" && -n "$LAST_ARTIST" ]]; then
                PLAY_TIME=$((CURRENT_TIME - TRACK_START_TIME))
                THRESHOLD=$((LAST_DURATION / 2))
                (( THRESHOLD > 240 )) && THRESHOLD=240

                if (( PLAY_TIME >= THRESHOLD && PLAY_TIME >= MIN_PLAY_TIME )); then
                    if should_scrobble "$LAST_ARTIST" "$LAST_TITLE" "$TRACK_TIMESTAMP"; then
                        if scrobble_track "$LAST_ARTIST" "$LAST_TITLE" "$TRACK_TIMESTAMP" "$LAST_ALBUM" "$LAST_DURATION"; then
                            SCROBBLED=true
                        fi
                    fi
                else
                    log "INFO" "Track not played long enough to scrobble: $PLAY_TIME seconds (need $THRESHOLD)"
                fi
            fi

            LAST_TITLE="$CURRENT_TITLE"
            LAST_ARTIST="$CURRENT_ARTIST"
            LAST_ALBUM="$CURRENT_ALBUM"
            LAST_DURATION="$CURRENT_DURATION"
            TRACK_START_TIME=$CURRENT_TIME
            TRACK_TIMESTAMP=$CURRENT_TIME
            SCROBBLED=false

            log "INFO" "Now playing: $CURRENT_ARTIST - $CURRENT_TITLE ($CURRENT_ALBUM)"
        elif [[ "$SCROBBLED" == "false" ]]; then
            PLAY_TIME=$((CURRENT_TIME - TRACK_START_TIME))
            THRESHOLD=$((CURRENT_DURATION / 2))
            (( THRESHOLD > 240 )) && THRESHOLD=240

            if (( PLAY_TIME >= THRESHOLD && PLAY_TIME >= MIN_PLAY_TIME )); then
                if should_scrobble "$CURRENT_ARTIST" "$CURRENT_TITLE" "$TRACK_TIMESTAMP"; then
                    if scrobble_track "$CURRENT_ARTIST" "$CURRENT_TITLE" "$TRACK_TIMESTAMP" "$CURRENT_ALBUM" "$CURRENT_DURATION"; then
                        SCROBBLED=true
                    fi
                fi
            else
                log "DEBUG" "Still playing: $CURRENT_ARTIST - $CURRENT_TITLE ($PLAY_TIME/$THRESHOLD seconds)"
            fi
        fi
    else
        if [[ -n "$LAST_TITLE" && -n "$LAST_ARTIST" && "$SCROBBLED" == "false" ]]; then
            CURRENT_TIME=$(date +%s)
            PLAY_TIME=$((CURRENT_TIME - TRACK_START_TIME))
            THRESHOLD=$((LAST_DURATION / 2))
            (( THRESHOLD > 240 )) && THRESHOLD=240

            if (( PLAY_TIME >= THRESHOLD && PLAY_TIME >= MIN_PLAY_TIME )); then
                if should_scrobble "$LAST_ARTIST" "$LAST_TITLE" "$TRACK_TIMESTAMP"; then
                    if scrobble_track "$LAST_ARTIST" "$LAST_TITLE" "$TRACK_TIMESTAMP" "$LAST_ALBUM" "$LAST_DURATION"; then
                        SCROBBLED=true
                    fi
                fi
            else
                log "INFO" "Last track not played long enough to scrobble: $PLAY_TIME seconds (need $THRESHOLD)"
            fi

            LAST_TITLE=""
            LAST_ARTIST=""
            LAST_ALBUM=""
            SCROBBLED=false
        fi
    fi
    sleep $POLL_INTERVAL
done
