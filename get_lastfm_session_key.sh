#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/apple_music_lastfm_scrobbler.sh"

echo "==== Last.fm Session Key Generator ===="
echo ""
read -p "Enter your Last.fm API key: " API_KEY
read -p "Enter your Last.fm API secret: " API_SECRET

if [[ -z "$API_KEY" || -z "$API_SECRET" ]]; then
    echo "Both API key and secret are required."
    exit 1
fi

echo ""
echo "Step 1: Open this URL in your browser:"
echo "https://www.last.fm/api/auth/?api_key=${API_KEY}&cb=http://localhost"
echo ""
echo "Step 2: Log in to Last.fm and authorize the app."
echo "Step 3: After being redirected to localhost, copy the 'token' from the URL."
echo ""
read -p "Enter the token from the URL: " TOKEN

if [ -z "$TOKEN" ]; then
    echo "No token provided. Please try again."
    exit 1
fi

echo ""
echo "Generating signature and requesting session key..."
# Cross-platform MD5 function
if command -v md5sum >/dev/null 2>&1; then
    # Linux systems with md5sum
    SIGNATURE=$(echo -n "api_key${API_KEY}methodauth.getSessiontoken${TOKEN}${API_SECRET}" | md5sum | cut -d ' ' -f 1)
else
    # macOS uses md5 -q
    SIGNATURE=$(echo -n "api_key${API_KEY}methodauth.getSessiontoken${TOKEN}${API_SECRET}" | md5 -q)
fi

RESPONSE=$(curl -s "http://ws.audioscrobbler.com/2.0/?method=auth.getSession&api_key=${API_KEY}&token=${TOKEN}&api_sig=${SIGNATURE}")

echo "API Response:"
echo "$RESPONSE"
echo ""

# Extract session key
SESSION_KEY=$(echo "$RESPONSE" | grep -o "<key>.*</key>" | sed 's/<key>\(.*\)<\/key>/\1/')

if [ -n "$SESSION_KEY" ]; then
    echo "Success! Your session key is: $SESSION_KEY"
    echo ""
    echo "Updating your scrobbler script..."

    cp "$SCRIPT_PATH" "${SCRIPT_PATH}.bak"

    sed -i '' \
        -e "s|^API_KEY=\"\".*|API_KEY=\"$API_KEY\"      # Your Last.fm API key|" \
        -e "s|^API_SECRET=\"\".*|API_SECRET=\"$API_SECRET\"   # Your Last.fm API shared secret|" \
        -e "s|^SESSION_KEY=\"\".*|SESSION_KEY=\"$SESSION_KEY\"  # Your Last.fm session key|" \
        "$SCRIPT_PATH"

    echo "Script updated with your credentials!"
    echo ""
    
    # Create LaunchAgent if it doesn't exist
    if [ ! -f ~/Library/LaunchAgents/com.user.apple_music_lastfm_scrobbler.plist ]; then
        echo "Creating LaunchAgent..."
        mkdir -p ~/Library/LaunchAgents
        cp "${SCRIPT_DIR}/com.user.apple_music_lastfm_scrobbler.plist" ~/Library/LaunchAgents/ 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "Warning: LaunchAgent plist file not found in the repository."
            echo "You'll need to create it manually to start the service at login."
        fi
    fi
    
    echo "Starting the scrobbler service..."
    launchctl unload ~/Library/LaunchAgents/com.user.apple_music_lastfm_scrobbler.plist 2>/dev/null
    launchctl load ~/Library/LaunchAgents/com.user.apple_music_lastfm_scrobbler.plist
    launchctl start com.user.apple_music_lastfm_scrobbler

    echo ""
    echo "Done! Your Apple Music to Last.fm scrobbler should now be running."
    echo "You can check the logs with:"
    echo "tail -f ~/Library/Logs/apple_music_lastfm_scrobbler.log"
else
    echo "Failed to extract session key from the response."
    echo "Please check the error message above and try again."
fi
