#!/bin/bash

API_KEY="256030787c8f6f3446004688dd1e6ded"
API_SECRET="28e59e4f6b03c1e772be0d861b049ac2"
SCRIPT_PATH="$HOME/apple_music_lastfm_scrobbler.sh"

echo "==== Last.fm Session Key Generator ===="
echo ""
echo "We'll help you get a session key for your Last.fm scrobbler."
echo ""
echo "Step 1: Open this URL in your browser:"
echo "https://www.last.fm/api/auth/?api_key=${API_KEY}&cb=http://localhost"
echo ""
echo "Step 2: Log in to Last.fm if necessary and authorize the application"
echo ""
echo "Step 3: After authorization, you'll be redirected to a page that won't load (localhost)"
echo "        Look in your browser's address bar for something like:"
echo "        http://localhost/?token=XXXXXXXXXXXXXXX"
echo ""
echo "Step 4: Copy the token from the URL (the part after 'token=')"
echo ""
echo -n "Enter the token from your browser: "
read TOKEN

if [ -z "$TOKEN" ]; then
    echo "No token provided. Please try again."
    exit 1
fi

echo ""
echo "Generating signature and requesting session key..."
SIGNATURE=$(echo -n "api_key${API_KEY}methodauth.getSessiontoken${TOKEN}${API_SECRET}" | md5sum | cut -d ' ' -f 1)

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
    
    # Make a backup of the original script
    cp "$SCRIPT_PATH" "${SCRIPT_PATH}.bak"
    
    # Update the credentials in the script
    sed -i '' \
        -e "s|^API_KEY=\"\".*|API_KEY=\"$API_KEY\"      # Your Last.fm API key|" \
        -e "s|^API_SECRET=\"\".*|API_SECRET=\"$API_SECRET\"   # Your Last.fm API shared secret|" \
        -e "s|^SESSION_KEY=\"\".*|SESSION_KEY=\"$SESSION_KEY\"  # Your Last.fm session key|" \
        "$SCRIPT_PATH"
    
    echo "Script updated with your credentials!"
    echo ""
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
