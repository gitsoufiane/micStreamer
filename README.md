# MicStreamer

MicStreamer is a macOS menu-bar app that sends app audio and your real
microphone into one virtual microphone.

Use it when you want people in Discord, Zoom, a game, or another call app to
hear music, YouTube, or any app audio, while you still hear the call normally.

## What it does

- Captures system audio with CoreAudio process taps.
- Sends captured audio to **BlackHole 2ch**.
- Optionally mixes your real microphone into the same BlackHole input.
- Avoids changing your Mac default output.

Your call app uses **BlackHole 2ch** as its microphone. Your call app output
must stay on your real headphones or speakers.

## Requirements

- macOS 14.2 or newer.
- Xcode Command Line Tools.
- Homebrew.
- BlackHole 2ch.

Install missing tools:

```sh
xcode-select --install
brew install blackhole-2ch
```

Restart audio apps after installing BlackHole. Restart the Mac if BlackHole asks
for it.

## Install from DMG

If a GitHub Release has `MicStreamer.dmg`, download it, open it, then drag
`MicStreamer.app` to **Applications**.

If macOS says the app is from an unidentified developer, right-click the app and
choose **Open**. MicStreamer is ad-hoc signed until Developer ID notarization is
added.

Homebrew install is planned after there is a versioned DMG release URL and
checksum.

## Build a DMG from source

Run these commands:

```sh
git clone https://github.com/gitsoufiane/micStreamer.git
cd micStreamer
./scripts/package-dmg.sh
open .build/release/MicStreamer.dmg
```

Then drag `MicStreamer.app` to **Applications**.

## Setup in your call app

In Discord, Zoom, your game, or your call app:

- Input: **BlackHole 2ch**.
- Output: your real headphones or speakers.

Do not set the call app output to BlackHole. If you do, you may stop hearing the
call or create echo.

## Use

1. Open MicStreamer.
2. Click the menu-bar mic icon.
3. Choose **Capture Source**:
   - **All Apps Except Calls** is the default.
   - Choose a music or browser app for the safest test.
4. Set **Music Volume** and **Mic Volume**.
5. Choose **Microphone** if you want a specific real microphone.
6. Keep **Include Microphone** enabled if people should hear your voice.
7. Click **Start Routing**.
8. Click **Stop Routing** when done.

The first time you start routing, macOS may ask for system-audio capture and
microphone permission. Allow both.

## Quick test

1. Open MicStreamer.
2. Click **Run BlackHole Self-Test**.
3. Expect: `BlackHole self-test passed. Test tone was detected.`

For a real audio test:

1. Open QuickTime Player.
2. Choose **File → New Audio Recording**.
3. In the record dropdown, choose **BlackHole 2ch** as the microphone.
4. Play music or YouTube.
5. In MicStreamer, choose that app under **Capture Source**.
6. Click **Start Routing**.
7. Record 10 seconds while you speak.
8. Play the recording back.

Expected result: the recording contains the app audio and your voice.

## Troubleshooting

- If BlackHole is missing, run `brew install blackhole-2ch`, then restart audio
  apps.
- If the app has no permission, open **System Settings → Privacy & Security**
  and allow MicStreamer for audio and microphone access.
- If a browser call echoes, do not use the same browser for the call and YouTube.
  Choose the music browser under **Capture Source**.
- If people cannot hear anything, confirm the call app input is **BlackHole 2ch**.
- If music or your voice is too loud or quiet, adjust **Music Volume** or
  **Mic Volume** in MicStreamer.

## Limits

- Browser calls and browser music share one process. MicStreamer cannot separate
  tabs yet.
- Games with built-in voice chat may need **Capture Source** set to the music app
  instead of **All Apps Except Calls**.
- **Music Volume** and **Mic Volume** use preset levels. Use the source app or
  call app controls if you need finer volume changes.
