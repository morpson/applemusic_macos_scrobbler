# Apple Music Last.fm Scrobbler

A bash script that automatically scrobbles tracks played in Apple Music to Last.fm on macOS.

## Features

- Scrobbles tracks from Apple Music to Last.fm
- Follows Last.fm's scrobbling rules (tracks must play for at least 30 seconds or half their duration)
- Prevents duplicate scrobbles
- Minimal system impact with configurable polling interval
- Runs as a LaunchAgent for automatic startup
- Detailed logging

## Prerequisites

- macOS with Apple Music app
- Last.fm account
- Last.fm API credentials (API key and secret)

## Installation

1. Clone this repository:

```bash
git clone https://github.com/morpson/applemusic_macos_scrobbler.git
cd applemusic_macos_scrobbler
```

2. Get your Last.fm API credentials:
   - Register for a Last.fm API account at <https://www.last.fm/api/account/create>
   - Note down your API key and API secret

3. Run the setup scripts in order:

```bash
chmod +x get_session_key.sh update_credentials.sh apple_music_lastfm_scrobbler.sh
./get_session_key.sh
./update_credentials.sh
```

4. Copy the script to your home directory:

```bash
cp apple_music_lastfm_scrobbler.sh ~/
```

5. Create the LaunchAgent to run on startup:

```bash
mkdir -p ~/Library/LaunchAgents
cat > ~/Library/LaunchAgents/com.user.apple_music_lastfm_scrobbler.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.apple_music_lastfm_scrobbler</string>
    <key>ProgramArguments</key>
    <array>
        <string>$HOME/apple_music_lastfm_scrobbler.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/apple_music_lastfm_scrobbler.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/apple_music_lastfm_scrobbler.error.log</string>
</dict>
</plist>
EOF
```

6. Load the LaunchAgent:

```bash
launchctl load ~/Library/LaunchAgents/com.user.apple_music_lastfm_scrobbler.plist
```

## Configuration

You can modify these variables in `apple_music_lastfm_scrobbler.sh`:

- `POLL_INTERVAL`: How often to check Apple Music (seconds)
- `MIN_PLAY_TIME`: Minimum seconds before tracking a new song
- `DEBUG`: Set to true for verbose logging

## Logging

View the scrobbler logs:

```bash
tail -f ~/Library/Logs/apple_music_lastfm_scrobbler.log
```

## Troubleshooting

If scrobbling stops working:

1. Check the logs for errors
2. Ensure Apple Music is running
3. Verify your Last.fm credentials are correct
4. Try restarting the service:

```bash
launchctl unload ~/Library/LaunchAgents/com.user.apple_music_lastfm_scrobbler.plist
launchctl load ~/Library/LaunchAgents/com.user.apple_music_lastfm_scrobbler.plist
```

## Files

- `apple_music_lastfm_scrobbler.sh`: Main scrobbling script
- `get_session_key.sh`: Helper script to obtain Last.fm session key
- `update_credentials.sh`: Helper script to update API credentials
