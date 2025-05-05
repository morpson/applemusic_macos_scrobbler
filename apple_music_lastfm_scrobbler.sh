#!/bin/bash
#
# Apple Music to Last.fm Scrobbler
# -------------------------------
# This script scrobbles tracks played in Apple Music to Last.fm
# with minimal impact on system performance.
#
# SETUP INSTRUCTIONS:
# 1. Register for a Last.fm API account at https://www.last.fm/api/account/create
#    - You'll receive an API key and shared secret
# 2. Get a session key by following the authentication process:
#    - Visit: https://www.last.fm/api/auth/?api_key=YOUR_API_KEY&cb=http://localhost
#    - After authorizing, you'll be redirected to a URL with a token
#    - Run this command to get your session key:
#      curl -s "http://ws.audioscrobbler.com/2.0/?method=auth.getSession&api_key=YOUR_API_KEY&token=TOKEN&api_sig=SIGNATURE"
#      (See Last.fm API docs for how to create the signature)
# 3. Fill in your API_KEY, API_SECRET, and SESSION_KEY below
# 4. Make this script executable: chmod +x apple_music_lastfm_scrobbler.sh
# 5. Run in background: nohup ./apple_music_lastfm_scrobbler.sh > scrobbler.log 2>&1 &
#
# For running as a LaunchAgent, see instructions at the end of the script.

# ===== CONFIGURATION SECTION =====
# Last.fm API credentials - YOU MUST FILL THESE IN
API_KEY=""      # Your Last.fm API key
API_SECRET=""   # Your Last.fm API shared secret
SESSION_KEY=""  # IXhG8wUsDJ5CZEQf8qgVDcIAYoUjhry3

# Configuration options
LOG_FILE="$HOME/Library/Logs/apple_music_lastfm_scrobbler.log"
CACHE_FILE="$HOME/.apple_music_lastfm_scrobbler_cache"
POLL_INTERVAL=10        # How often to check Apple Music (seconds)
MIN_PLAY_TIME=30        # Minimum seconds before tracking a new song
DEBUG=false             # Set to true for verbose logging

# ===== UTILITY FUNCTIONS =====

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    if [[ "$level" == "DEBUG" && "$DEBUG" != "true" ]]; then
        return
    fi
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # Also print to stdout if not running in background
    if [ -t 1 ]; then
        echo "[$timestamp] [$level] $message"
    fi
}

# Generate MD5 hash for Last.fm API signature
md5() {
    echo -n "$1" | md5sum | cut -d ' ' -f 1
}

# URL encode a string
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

# Create Last.fm API signature
create_signature() {
    local params="$1"
    local string=""
    
    # Sort parameters alphabetically
    IFS=$'\n' sorted=($(sort <<< "$params"))
    unset IFS
    
    # Create string to sign
    for param in "${sorted[@]}"; do
        string="${string}${param}"
    done
    string="${string}${API_SECRET}"
    
    # Return MD5 hash
    md5 "$string"
}

# Submit a track scrobble to Last.fm
scrobble_track() {
    local artist="$1"
    local track="$2"
    local timestamp="$3"
    local album="$4"
    local duration="$5"
    
    log "INFO" "Scrobbling track: $artist - $track ($album) with timestamp $timestamp"
    
    # URL encode parameters
    local artist_enc=$(urlencode "$artist")
    local track_enc=$(urlencode "$track")
    local album_enc=$(urlencode "$album")
    
    # Create parameter string for signature
    local params=""
    params+="api_key${API_KEY}"
    params+="artist${artist}"
    params+="method${method}"
    params+="sk${SESSION_KEY}"
    params+="timestamp${timestamp}"
    params+="track${track}"
    
    if [[ -n "$album" ]]; then
        params+="album${album}"
    fi
    
    if [[ -n "$duration" ]]; then
        params+="duration${duration}"
    fi
    
    local method="track.scrobble"
    local signature=$(create_signature "$params")
    
    # Build POST data
    local post_data="method=${method}&api_key=${API_KEY}&artist=${artist_enc}&track=${track_enc}&timestamp=${timestamp}&api_sig=${signature}&sk=${SESSION_KEY}"
    
    if [[ -n "$album" ]]; then
        post_data+="&album=${album_enc}"
    fi
    
    if [[ -n "$duration" ]]; then
        post_data+="&duration=${duration}"
    fi
    
    # Make API request
    local response=$(curl -s -d "$post_data" "https://ws.audioscrobbler.com/2.0/")
    
    # Check response
    if echo "$response" | grep -q "status=\"ok\""; then
        log "INFO" "Successfully scrobbled: $artist - $track"
        # Save to scrobble cache to prevent duplicates
        echo "$artist - $track - $timestamp" >> "$CACHE_FILE"
        return 0
    else
        log "ERROR" "Failed to scrobble track: $response"
        return 1
    fi
}

# Check if Apple Music is running
is_music_running() {
    pgrep -q "Music"
    return $?
}

# Get current track info from Apple Music
get_current_track() {
    # Get track information using AppleScript
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
    
    if [[ -z "$track_info" ]]; then
        return 1
    fi
    
    # Parse track information
    IFS='|' read -r title artist album duration position <<< "$track_info"
    
    # Return as global variables
    CURRENT_TITLE="$title"
    CURRENT_ARTIST="$artist"
    CURRENT_ALBUM="$album"
    CURRENT_DURATION="$duration"
    CURRENT_POSITION="$position"
    
    log "DEBUG" "Track: $CURRENT_ARTIST - $CURRENT_TITLE ($CURRENT_ALBUM) Position: $CURRENT_POSITION/$CURRENT_DURATION"
    return 0
}

# Check if we should scrobble the current track
should_scrobble() {
    local artist="$1"
    local title="$2"
    local timestamp="$3"
    
    # Ignore if artist or title is empty
    if [[ -z "$artist" || -z "$title" ]]; then
        return 1
    fi
    
    # Check cache to prevent duplicate scrobbles
    if grep -q "$artist - $title - $timestamp" "$CACHE_FILE"; then
        log "DEBUG" "Track already scrobbled: $artist - $title"
        return 1
    fi
    
    return 0
}

# Clean up resources
cleanup() {
    log "INFO" "Shutting down scrobbler"
    exit 0
}

# ===== MAIN SCRIPT =====

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Ensure log and cache files exist
touch "$LOG_FILE"
touch "$CACHE_FILE"

# Trim cache file to prevent it from getting too large
tail -n 1000 "$CACHE_FILE" > "${CACHE_FILE}.tmp" && mv "${CACHE_FILE}.tmp" "$CACHE_FILE"

# Initialize variables
LAST_TITLE=""
LAST_ARTIST=""
LAST_ALBUM=""
TRACK_START_TIME=0
TRACK_TIMESTAMP=0
SCROBBLED=false

log "INFO" "Apple Music to Last.fm scrobbler started"

# Check if API credentials are set
if [[ -z "$API_KEY" || -z "$API_SECRET" || -z "$SESSION_KEY" ]]; then
    log "ERROR" "Please set your Last.fm API credentials in the script"
    exit 1
fi

# Main loop
while true; do
    # Check if Apple Music is playing
    if get_current_track; then
        CURRENT_TIME=$(date +%s)
        
        # Track changed?
        if [[ "$CURRENT_TITLE" != "$LAST_TITLE" || "$CURRENT_ARTIST" != "$LAST_ARTIST" ]]; then
            log "INFO" "Track changed: $CURRENT_ARTIST - $CURRENT_TITLE"
            
            # Scrobble previous track if it played long enough
            if [[ "$SCROBBLED" == "false" && -n "$LAST_TITLE" && -n "$LAST_ARTIST" ]]; then
                # Calculate play time
                PLAY_TIME=$((CURRENT_TIME - TRACK_START_TIME))
                
                # Last.fm rules: scrobble if played for 4 minutes or half the track length, whichever comes first
                THRESHOLD=$(echo "$CURRENT_DURATION/2" | bc)
                if (( THRESHOLD > 240 )); then
                    THRESHOLD=240
                fi
                
                if (( PLAY_TIME >= THRESHOLD && PLAY_TIME >= MIN_PLAY_TIME )); then
                    if should_scrobble "$LAST_ARTIST" "$LAST_TITLE" "$TRACK_TIMESTAMP"; then
                        scrobble_track "$LAST_ARTIST" "$LAST_TITLE" "$TRACK_TIMESTAMP" "$LAST_ALBUM" "$CURRENT_DURATION"
                    fi
                else
                    log "INFO" "Track not played long enough to scrobble: $PLAY_TIME seconds (need $THRESHOLD)"
                fi
            fi
            
            # Start tracking new track
            LAST_TITLE="$CURRENT_TITLE"
            LAST_ARTIST="$CURRENT_ARTIST"
            LAST_ALBUM="$CURRENT_ALBUM"
            TRACK_START_TIME=$CURRENT_TIME
            TRACK_TIMESTAMP=$CURRENT_TIME
            SCROBBLED=false
            
            log "INFO" "Now playing: $CURRENT_ARTIST - $CURRENT_TITLE ($CURRENT_ALBUM)"
        elif [[ "$SCROBBLED" == "false" ]]; then
            # Same track is still playing, check if we should scrobble it now
            PLAY_TIME=$((CURRENT_TIME - TRACK_START_TIME))
            
            # Last.fm rules: scrobble if played for 4 minutes or half the track length, whichever comes first
            THRESHOLD=$(echo "$CURRENT_DURATION/2" | bc)
            if (( THRESHOLD > 240 )); then
                THRESHOLD=240
            fi
            
            if (( PLAY_TIME >= THRESHOLD && PLAY_TIME >= MIN_PLAY_TIME )); then
                if should_scrobble "$CURRENT_ARTIST" "$CURRENT_TITLE" "$TRACK_TIMESTAMP"; then
                    scrobble_track "$CURRENT_ARTIST" "$CURRENT_TITLE" "$TRACK_TIMESTAMP" "$CURRENT_ALBUM" "$CURRENT_DURATION"
                    SCROBBLED=true
                fi
            else
                log "DEBUG" "Still playing: $CURRENT_ARTIST - $CURRENT_TITLE ($PLAY_TIME/$THRESHOLD seconds)"
            fi
        fi
    else
        # Music is not playing or app is closed
        if [[ -n "$LAST_TITLE" && -n "$LAST_ARTIST" && "$SCROBBLED" == "false" ]]; then
            # Calculate play time for the last track before playback stopped
            CURRENT_TIME=$(date +%s)
            PLAY_TIME=$((CURRENT_TIME - TRACK_START_TIME))
            
            # Last.fm rules: scrobble if played for 4 minutes or half the track length, whichever comes first
            THRESHOLD=$(echo "$CURRENT_DURATION/2" | bc)
            if (( THRESHOLD > 240 )); then
                THRESHOLD=240
            fi
            
            if (( PLAY_TIME >= THRESHOLD && PLAY_TIME >= MIN_PLAY_TIME )); then
                if should_scrobble "$LAST_ARTIST" "$LAST_TITLE" "$TRACK_TIMESTAMP"; then
                    scrobble_track "$LAST_ARTIST" "$LAST_TITLE" "$TRACK_TIMESTAMP" "$LAST_ALBUM" "$CURRENT_DURATION"
                fi
            else
                log "INFO" "Last track not played long enough to scrobble: $PLAY_TIME seconds (need $THRESHOLD)"
            fi
            
            # Reset tracking
            LAST_TITLE=""
            LAST_ARTIST=""
            LAST_ALBUM=""
            SCROBBLED=false
        fi
    fi
    
    # Sleep to reduce system impact
    sleep $POLL_INTERVAL
done

# ===== LAUNCHD SETUP INSTRUCTIONS =====
# To run this script automatically when you log in, create a LaunchAgent:
#
# 1. Create this file: ~/Library/LaunchAgents/com.user.apple_music_lastfm_scrobbler.plist
# 2. Paste this content (adjust paths as needed):
#
# <?xml version="1.0" encoding="UTF-8"?>
# <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
# <plist version="1.0">
# <dict>
#     <key>Label</key>
#     <string>com.user.apple_music_lastfm_scrobbler</string>
#     <key>ProgramArguments</key>
#     <array>
#         <string>/Users/YOUR_USERNAME/apple_music_lastfm_scrobbler.sh</string>
#     </array>
#     <key>RunAtLoad</key>
#     <true/>
#     <key>KeepAlive</key>
#     <true/>
#     <key>StandardOutPath</key>
#     <string>/Users/YOUR_USERNAME/Library/Logs/apple_music_lastfm_scrobbler.log</string

