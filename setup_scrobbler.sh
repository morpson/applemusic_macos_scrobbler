#!/bin/bash

# Apple Music Last.fm Scrobbler - One-Step Setup
# This script personalizes and installs the scrobbler LaunchAgent with your username and chosen script location.
set -e

PLIST_SRC="com.user.apple_music_lastfm_scrobbler.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/com.user.apple_music_lastfm_scrobbler.plist"
DEFAULT_SCRIPT_PATH="$PWD/apple_music_lastfm_scrobbler.sh"

echo "==== Apple Music Last.fm Scrobbler Automated Setup ===="
echo

# 1. Ensure main script is executable in current repo or in user's $HOME
if [ -f "$DEFAULT_SCRIPT_PATH" ]; then
    SCRIPT_PATH="$DEFAULT_SCRIPT_PATH"
elif [ -f "$HOME/apple_music_lastfm_scrobbler.sh" ]; then
    SCRIPT_PATH="$HOME/apple_music_lastfm_scrobbler.sh"
else
    echo "Main script (apple_music_lastfm_scrobbler.sh) not found in current directory or home. Aborting."
    exit 1
fi

chmod +x "$SCRIPT_PATH"
echo "Ensured $SCRIPT_PATH is executable."

# 2. Personalize the plist with actual username and script location
if [ ! -f "$PLIST_SRC" ]; then
    echo "ERROR: $PLIST_SRC not found in repo root. Aborting."
    exit 1
fi

cp "$PLIST_SRC" "$PLIST_DEST"

# Substitute USERNAME with the current username, and set absolute paths
USERNAME=$(whoami)
LOG_PATH="$HOME/Library/Logs/apple_music_lastfm_scrobbler.log"

# Use sed -i '' for macOS
sed -i '' \
    -e "s|/Users/USERNAME/apple_music_lastfm_scrobbler.sh|$SCRIPT_PATH|g" \
    -e "s|/Users/USERNAME/Library/Logs/apple_music_lastfm_scrobbler.log|$LOG_PATH|g" \
    "$PLIST_DEST"

echo "Personalized LaunchAgent plist and copied to $PLIST_DEST."

# 3. Instruct the user to set up credentials with appropriate script
CRED_STATUS="not-set"
if grep -q 'USE_KEYCHAIN=true' "$SCRIPT_PATH"; then
    if ./secure_credentials.sh test >/dev/null 2>&1; then
        CRED_STATUS="keychain"
    fi
elif grep -qE '^API_KEY="[A-Z0-9]"' "$SCRIPT_PATH"; then
    CRED_STATUS="script"
fi

echo
echo "==== Credentials Setup ===="
if [ "$CRED_STATUS" = "keychain" ]; then
    echo "✅ Credentials already securely stored in Keychain."
elif [ "$CRED_STATUS" = "script" ]; then
    echo "✅ Credentials found in script file."
else
    echo "You need to set up your Last.fm API credentials."
    echo "Choose one of the following:"
    echo "  1. Interactive (recommended): ./get_lastfm_session_key.sh"
    echo "  2. Secure:                    ./secure_credentials.sh store"
    echo "  3. Manual:                    ./update_scrobbler_credentials.sh"
    echo
    echo "Follow prompts, then re-run this setup script if you change how credentials are stored."
    read -p "Press Enter to continue once credentials are configured..."
fi

# 4. Make sure LaunchAgents and Log dirs exist
mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$HOME/Library/Logs"

# 5. (Re)load the service
launchctl unload "$PLIST_DEST" 2>/dev/null || true
launchctl load "$PLIST_DEST"
launchctl start com.user.apple_music_lastfm_scrobbler

echo
echo "🎉 Done! Scrobbler configured and set to run at login. To check logs:"
echo "    tail -f $LOG_PATH"
echo
echo "To reconfigure, re-run this script. To remove, run:"
echo "    launchctl unload \"$PLIST_DEST\"; rm \"$PLIST_DEST\""