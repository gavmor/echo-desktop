# Live Audio Transcriber

This program provides real-time transcription of both system audio (e.g., Firefox, Zoom, Spotify) and your microphone using `whisper.cpp`. It implements advanced audio routing to ensure you can hear the audio while it is being transcribed without hearing a delayed echo of your own voice.

## Features

- **Split Audio Routing**: Hear application audio through your headphones while a copy is sent to the transcriber.
- **Microphone Merging**: Transcribe your own voice alongside system audio.
- **Dynamic Routing**: Can "hijack" audio from already-running applications.
- **Automatic Setup**: Handles cloning, building, and model downloading for `whisper.cpp`.

## Prerequisites

- **Linux** with PulseAudio or PipeWire (with `pipewire-pulse`).
- `build-essential`, `git`, `cmake`, `libsdl2-dev`, and `pactl`.
  - On Ubuntu/Debian: `sudo apt install build-essential git cmake libsdl2-dev pulseaudio-utils`

## Installation & Usage

1. **Make the script executable**:
   ```bash
   chmod +x transcribe.sh
   ```

2. **Start Transcribing**:
   The script will automatically handle the build process using `cmake`. It specifically looks for the `whisper-stream` example, which requires SDL2.

   ### Method A: Launch a new application
   Force an application to use the virtual splitter from the start:
   ```bash
   PULSE_SINK=SplitSink firefox &
   ./transcribe.sh
   ```

   ### Method B: Move an existing application
   If the application is already running and playing audio, pass its name as an argument:
   ```bash
   ./transcribe.sh Firefox
   ```

3. **View Results**:
   Transcription is streamed to the terminal and saved to:
   `whisper.cpp/transcription_log.txt`

## How it Works

The script creates two virtual devices:
1. **SplitSink (The Splitter)**: A `module-combine-sink` that clones audio to your hardware speakers AND the mixer.
2. **WhisperMixSink (The Mixer)**: A `module-null-sink` that combines the application audio copy with your microphone input.

`whisper.cpp` listens exclusively to the **Mixer**, while you listen to the **Splitter**.

## Cleanup

Simply press `Ctrl+C` in the terminal running `transcribe.sh`. The script will automatically unload the virtual audio modules and clean up the routing.
