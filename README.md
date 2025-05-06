<table>
  <tr>
    <td width="300" valign="middle">
      <img src="assets/icon.png" width="268" alt="Apple Music Scrobbler Icon">
    </td>
    <td valign="middle">
      <h1>Apple Music to Last.fm - macOS Scrobbler</h1>
    </td>
  </tr>
</table>

This tool automatically scrobbles your currently playing Apple Music tracks to [Last.fm](https://www.last.fm). It runs in the background on macOS using AppleScript and a `launchd` service.

---

## 🚀 One-Step Automatic Installation

For the fastest setup after cloning, **run our automatic setup script**. It will:
- Ensure the main script is executable
- Personalize and install the LaunchAgent plist with your username and correct script/log paths
- Guide you through credential setup with the appropriate method
- Reload and start the scrobbler service

**Usage:**

```bash
git clone https://github.com/morpson/applemusic_macos_scrobbler.git
cd applemusic_macos_scrobbler
chmod +x setup_scrobbler.sh
./setup_scrobbler.sh
```

Just follow the prompts. Once complete, the scrobbler will autostart with macOS login or, with the new plist, automatically start whenever you open the Apple Music app.

> **Tip:** For most users, this is all you need!  
> You can still follow the advanced/manual instructions below for greater control.

---

## ⚙️ Requirements

* macOS with Apple Music app
* A Last.fm account
* [Last.fm API account](https://www.last.fm/api/account/create) (to obtain your API key & secret)
* Command line tools: `bash`, `osascript`, `curl`, and one of `md5sum` (via `coreutils`) or `md5` (native on macOS)

---

## 🚀 Installation

1. **Clone the repository:**

```bash
git clone https://github.com/morpson/applemusic_macos_scrobbler.git
cd applemusic_macos_scrobbler
```

2. **Install the scrobbler script:**

You can install the script either in your home directory or keep it in the cloned repository:

```bash
# Option 1: Install to home directory (recommended for regular use)
cp apple_music_lastfm_scrobbler.sh ~/
chmod +x ~/apple_music_lastfm_scrobbler.sh

# Option 2: Keep it in the repository (easier for development)
chmod +x ./apple_music_lastfm_scrobbler.sh
```

3. **Install the launch agent to auto-start with Apple Music:**

**New!** The scrobbler can be set to automatically start and stop in sync with Apple Music using the provided LaunchAgent plist.

#### a. Copy and edit the LaunchAgent plist

Copy `com.user.apple_music_lastfm_scrobbler.plist` from this repo to your repository root (if needed), then edit the file to set the script and log paths to your user directory if different.

#### b. Install the plist and load it

```bash
mkdir -p ~/Library/LaunchAgents
cp com.user.apple_music_lastfm_scrobbler.plist ~/Library/LaunchAgents/
launchctl unload ~/Library/LaunchAgents/com.user.apple_music_lastfm_scrobbler.plist 2>/dev/null
launchctl load ~/Library/LaunchAgents/com.user.apple_music_lastfm_scrobbler.plist
```

> **With this plist, the scrobbler will start automatically every time you open the Apple Music app and will stop when you quit Music.**

---

## 🔐 Set Up Your Last.fm Credentials

To allow the script to scrobble to your Last.fm account, you'll need a **session key**. We provide two options:

### 🔁 Option 1: Interactive Setup (Recommended)

Run this script to guide you through the process of authenticating with Last.fm and updating the main script:

```bash
./get_lastfm_session_key.sh
```

This script will:

* Prompt for your **API key** and **API secret**
* Open the authorization URL in your browser
* Ask you to paste in the returned **token**
* Exchange it for a **session key**
* Insert all three values into your scrobbler script

✅ At the end, the script will automatically start the background scrobbler service.

---

### 🛠️ Option 2: Manual Setup (if you already have credentials)

If you already have:

* An **API key**
* An **API secret**
* A valid **session key**

Then run:

```bash
./update_scrobbler_credentials.sh
```

It will prompt you for these values and update the scrobbler script accordingly.

---

### 🔒 Option 3: Secure Credentials Storage (Enhanced Security)

For enhanced security, you can store your Last.fm API credentials in the macOS Keychain rather than directly in the script:

```bash
chmod +x ./secure_credentials.sh
./secure_credentials.sh store
```

This will:

* Prompt you for your **API key**, **API secret**, and **session key**
* Store all credentials securely in the macOS Keychain
* Update the scrobbler script to load credentials from the Keychain
* No sensitive information will be stored in the script file itself

To verify your credentials are properly stored and accessible:

```bash
./secure_credentials.sh test
```

If you want to revert back to storing credentials in the script file, set `USE_KEYCHAIN=false` in the script and run the update_scrobbler_credentials.sh script to set them directly.

---

## 🔄 Start / Reload the Scrobbler

* With the new LaunchAgent, the scrobbler will start with Apple Music—no extra commands are required!
* To manually reload:
```bash
launchctl unload ~/Library/LaunchAgents/com.user.apple_music_lastfm_scrobbler.plist
launchctl load ~/Library/LaunchAgents/com.user.apple_music_lastfm_scrobbler.plist
```

## 🛠️ Troubleshooting

- **Scrobbler won't start?**
    - Confirm the `.plist` file is present at `~/Library/LaunchAgents`, points to the correct username, script, and log paths.
    - Ensure your scrobbler script is marked executable.
    - Review logs in `~/Library/Logs/apple_music_lastfm_scrobbler.log`.

For additional credential setup, uninstall information, and further security tips, see remaining sections below.

## ✅ Quickstart after Clone

1. Clone, make the script executable.
2. Edit and install the LaunchAgent plist (new auto music-launch version!).
3. Set up your Last.fm credentials.
4. Load the LaunchAgent.
5. Play a track in Apple Music, check logs to confirm scrobbling.

---

## ✨ Notes

- **Advanced users:** The provided LaunchAgent can be further customized to support other logic; refer to Apple documentation for advanced plist keys.

---

## 🧪 Test It Works

Play a track in Apple Music. Then check the logs:

```bash
tail -f ~/Library/Logs/apple_music_lastfm_scrobbler.log
```

You should see output indicating the currently playing track and scrobble status. The script checks for new tracks every 30 seconds by default. You can adjust this interval by changing the `POLL_INTERVAL` value in the script if you prefer more or less frequent checks.

---

## 🧹 Uninstall

To remove the scrobbler:

```bash
launchctl unload ~/Library/LaunchAgents/com.user.apple_music_lastfm_scrobbler.plist
rm ~/Library/LaunchAgents/com.user.apple_music_lastfm_scrobbler.plist
rm ~/apple_music_lastfm_scrobbler.sh
```

---

## 🔒 Security Note

Do **not** share your API key, API secret, or session key publicly. The scripts are designed to prompt for your credentials securely — no sensitive data is stored in version control.

For even better security, consider storing your credentials in the macOS Keychain instead of directly in the script.

---

## 📄 License

MIT License — see `LICENSE` file.
