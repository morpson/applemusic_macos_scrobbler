#!/bin/bash

# Secure Credentials Helper for Apple Music Last.fm Scrobbler
# ---------------------------------------------------------
# This script helps you store and retrieve Last.fm API credentials
# securely using the macOS Keychain.

# Service name used for the keychain entries
SERVICE_NAME="com.user.applemusic_lastfm_scrobbler"

# Function to store a credential in the keychain
store_credential() {
    local account_name="$1"
    local credential="$2"
    
    # Delete existing entry if it exists
    security delete-generic-password -a "$account_name" -s "$SERVICE_NAME" 2>/dev/null
    
    # Store the new credential
    if security add-generic-password -a "$account_name" -s "$SERVICE_NAME" -w "$credential"; then
        echo "✅ Successfully stored $account_name in Keychain"
        return 0
    else
        echo "❌ Failed to store $account_name in Keychain"
        return 1
    fi
}

# Function to retrieve a credential from the keychain
get_credential() {
    local account_name="$1"
    security find-generic-password -a "$account_name" -s "$SERVICE_NAME" -w 2>/dev/null
    return $?
}

# Function to store all Last.fm API credentials
store_lastfm_credentials() {
    echo "Storing Last.fm API credentials in the macOS Keychain..."
    echo ""
    
    read -p "Enter your Last.fm API key: " API_KEY
    read -p "Enter your Last.fm API secret: " API_SECRET
    read -p "Enter your Last.fm session key: " SESSION_KEY
    
    if [[ -z "$API_KEY" || -z "$API_SECRET" || -z "$SESSION_KEY" ]]; then
        echo "All fields are required. Please try again."
        exit 1
    fi
    
    store_credential "lastfm_api_key" "$API_KEY" || exit 1
    store_credential "lastfm_api_secret" "$API_SECRET" || exit 1
    store_credential "lastfm_session_key" "$SESSION_KEY" || exit 1
    
    echo ""
    echo "Updating the main scrobbler script to use Keychain credentials..."
    
    # Get the directory where this script is located
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SCRIPT_PATH="${SCRIPT_DIR}/apple_music_lastfm_scrobbler.sh"
    
    # Make a backup of the original script
    cp "$SCRIPT_PATH" "${SCRIPT_PATH}.bak"
    
    # Update the script to use keychain
    sed -i '' \
        -e 's|^API_KEY=".*"|API_KEY="" # Will be loaded from Keychain|' \
        -e 's|^API_SECRET=".*"|API_SECRET="" # Will be loaded from Keychain|' \
        -e 's|^SESSION_KEY=".*"|SESSION_KEY="" # Will be loaded from Keychain|' \
        -e 's|^USE_KEYCHAIN=false|USE_KEYCHAIN=true|' \
        "$SCRIPT_PATH"
    
    echo "✅ All credentials stored securely in macOS Keychain"
    echo "✅ Main script updated to use Keychain for credentials"
    echo ""
    echo "The scrobbler will now automatically load credentials from Keychain."
    echo "To go back to storing credentials in the script, set USE_KEYCHAIN=false"
    echo "in the script and run update_scrobbler_credentials.sh to set them directly."
}

# Function to test Keychain access 
test_keychain_access() {
    echo "Testing Keychain access..."
    
    API_KEY=$(get_credential "lastfm_api_key")
    API_SECRET=$(get_credential "lastfm_api_secret")
    SESSION_KEY=$(get_credential "lastfm_session_key")
    
    if [[ -z "$API_KEY" || -z "$API_SECRET" || -z "$SESSION_KEY" ]]; then
        echo "❌ Failed to retrieve credentials from Keychain."
        echo "Some credentials were missing."
        return 1
    else
        echo "✅ Successfully retrieved all credentials from Keychain!"
        return 0
    fi
}

# Show usage information if no arguments
if [ $# -eq 0 ]; then
    echo "Apple Music Last.fm Scrobbler - Secure Credentials Helper"
    echo ""
    echo "Usage:"
    echo "  ./secure_credentials.sh store     # Store credentials in Keychain"
    echo "  ./secure_credentials.sh test      # Test Keychain access"
    echo ""
    exit 0
fi

# Process command line arguments
case "$1" in
    store)
        store_lastfm_credentials
        ;;
    test)
        test_keychain_access
        ;;
    *)
        echo "Unknown command: $1"
        echo "Usage: ./secure_credentials.sh [store|test]"
        exit 1
        ;;
esac

