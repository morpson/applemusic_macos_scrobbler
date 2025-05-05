#!/bin/bash

# Define a function to modify the scrobbler script
update_script() {
    local api_key="$1"
    local api_secret="$2"
    local session_key="$3"
    local script_path="$HOME/apple_music_lastfm_scrobbler.sh"
    
    # Make a backup of the original script
    cp "$script_path" "${script_path}.bak"
    
    # Update the credentials in the script
    sed -i '' \
        -e "s|^API_KEY=\"\".*|API_KEY=\"$api_key\"      # Your Last.fm API key|" \
        -e "s|^API_SECRET=\"\".*|API_SECRET=\"$api_secret\"   # Your Last.fm API shared secret|" \
        -e "s|^SESSION_KEY=\"\".*|SESSION_KEY=\"$session_key\"  # Your Last.fm session key|" \
        "$script_path"
    
    echo "Script updated with your credentials!"
}

# Print instructions
echo "Let's update your Apple Music to Last.fm scrobbler with your credentials."
echo "We'll need your Last.fm API key, API secret, and session key."
echo ""

# Check if credentials were already provided
API_KEY="256030787c8f6f3446004688dd1e6ded"
API_SECRET="28e59e4f6b03c1e772be0d861b049ac2"

echo "Using API key: $API_KEY"
echo "Using API secret: $API_SECRET"
echo ""
echo "Now we need a session key. Did you successfully generate one in the previous steps?"
echo "If yes, please enter it below. If not, we'll need to get a new token and generate one."
echo ""
echo "Session key (leave empty if you don't have one):"
