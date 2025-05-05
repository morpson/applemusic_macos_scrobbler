#!/bin/bash

# Define a function to modify the scrobbler script
update_script() {
    local api_key="$1"
    local api_secret="$2"
    local session_key="$3"
    
    # Get the directory where this script is located
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local script_path="${script_dir}/apple_music_lastfm_scrobbler.sh"

    # Make a backup of the original script
    cp "$script_path" "${script_path}.bak"

    # Update the credentials in the script
    sed -i '' \
        -e "s|^API_KEY=\"\".*|API_KEY=\"$api_key\"      # Your Last.fm API key|" \
        -e "s|^API_SECRET=\"\".*|API_SECRET=\"$api_secret\"   # Your Last.fm API shared secret|" \
        -e "s|^SESSION_KEY=\"\".*|SESSION_KEY=\"$session_key\"  # Your Last.fm session key|" \
        "$script_path"

    echo "Script updated with your credentials!"
    
    # Create LaunchAgent if it doesn't exist
    if [ ! -f ~/Library/LaunchAgents/com.user.apple_music_lastfm_scrobbler.plist ]; then
        echo "Creating LaunchAgent..."
        mkdir -p ~/Library/LaunchAgents
        cp "${script_dir}/com.user.apple_music_lastfm_scrobbler.plist" ~/Library/LaunchAgents/ 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "Warning: LaunchAgent plist file not found in the repository."
            echo "You'll need to create it manually to start the service at login."
        fi
    fi
    
    echo "To start the scrobbler service, run:"
    echo "launchctl unload ~/Library/LaunchAgents/com.user.apple_music_lastfm_scrobbler.plist 2>/dev/null"
    echo "launchctl load ~/Library/LaunchAgents/com.user.apple_music_lastfm_scrobbler.plist"
    echo "launchctl start com.user.apple_music_lastfm_scrobbler"
}

echo "Let's update your Apple Music to Last.fm scrobbler with your credentials."
echo ""

read -p "Enter your Last.fm API key: " API_KEY
read -p "Enter your Last.fm API secret: " API_SECRET
read -p "Enter your Last.fm session key: " SESSION_KEY

if [[ -z "$API_KEY" || -z "$API_SECRET" || -z "$SESSION_KEY" ]]; then
    echo "All fields are required. Please try again."
    exit 1
fi

update_script "$API_KEY" "$API_SECRET" "$SESSION_KEY"
