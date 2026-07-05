# MicStreamer

MicStreamer is a small macOS menu-bar app that sends system audio and your
microphone into a virtual microphone.

## Stack

- Swift + AppKit for a native menu-bar app.
- CoreAudio process taps for system-audio capture on macOS 14.2+.
- AVFoundation for sending the selected microphone into BlackHole.
- BlackHole 2ch as the virtual microphone.

This avoids changing the macOS default output. The app captures audio, sends the
captured stream to BlackHole, and your call app uses BlackHole as its input.

Sources:

- BlackHole README: <https://github.com/ExistentialAudio/BlackHole>
- Apple Audio Server Driver sample: <https://developer.apple.com/documentation/coreaudio/creating-an-audio-server-driver-plug-in>
- Apple Core Audio taps sample: <https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps>

## Requirements

- macOS 14.2 or newer.
- BlackHole 2ch installed.

## One-time setup

1. Install BlackHole 2ch:

   ```sh
   brew install blackhole-2ch
   ```

2. Restart audio apps, or restart the Mac if BlackHole asks for it.
3. In Discord, Zoom, your game, or your call app, set:
   - Input: **BlackHole 2ch**.
   - Output: your real headphones or speakers. Do not use BlackHole here.
4. Allow MicStreamer when macOS asks for system-audio capture permission.
5. If the call app cannot use the mic, allow it in
   **System Settings → Privacy & Security → Microphone**.

## Use

1. Build and open the app:

   ```sh
   ./scripts/build-app.sh
   open .build/release/MicStreamer.app
   ```

2. Click the menu-bar mic icon.
3. Choose **Capture Source**:
   - **All Apps Except Calls** is the default.
   - Choose a music/browser app for the safest call test.
4. Optional: choose **Microphone** and pick your real microphone.
5. Keep **Include Microphone** enabled if people should hear your voice.
6. Click **Start Routing**.
7. Click **Stop Routing** when done.

## Self-test

Use **Run BlackHole Self-Test** from the menu. It sends a test tone into
BlackHole and checks that BlackHole input can hear it.

## Microphone mix

When **Include Microphone** is on, MicStreamer sends your selected microphone to
BlackHole too. It is enabled by default. The call app hears both the captured
system audio and your voice.

The first time you enable it, macOS asks for microphone permission. If you deny
it, allow MicStreamer in **System Settings → Privacy & Security → Microphone**.

## Limits

- Browser calls and browser music share one app process. If you use Google Meet
  and YouTube in the same browser, MicStreamer cannot separate those tabs yet.
- Games with built-in voice chat may need **Capture Source** set to the music app
  instead of **All Apps Except Calls** to avoid echo.
- This version has no volume slider. Use source-app volume and system input
  volume.
