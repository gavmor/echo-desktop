To fully automate this without touching a GUI, we can use a "Null Sink" (essentially a virtual audio cable) via PulseAudio's command-line utilities. Because PipeWire includes a PulseAudio compatibility layer (`pipewire-pulse`), these commands work perfectly on modern Linux distributions.

The cleanest way to script this is by utilizing the `PULSE_SINK` and `PULSE_SOURCE` environment variables. This allows us to force specific applications to use our virtual cable right as they launch, completely bypassing the need to hunt down dynamic stream IDs.

Here is a complete, executable Bash script that sets up the routing, launches the applications, and cleans up after itself.

### The Automation Script

Save this as `transcribe_firefox.sh` and make it executable (`chmod +x transcribe_firefox.sh`). Ensure you run this from within your `whisper.cpp` directory.

```bash
#!/bin/bash

# Exit if any command fails
set -e

# 1. Create a virtual audio device (Null Sink)
# This acts as our invisible patch cable.
echo "Creating virtual audio cable..."
SINK_ID=$(pactl load-module module-null-sink sink_name=WhisperSink sink_properties=device.description="Whisper_Routing")

# Ensure cleanup happens even if you forcefully exit (Ctrl+C)
trap 'echo "Cleaning up..."; pactl unload-module $SINK_ID; exit' INT TERM EXIT

# 2. Launch Firefox, forcing its audio output directly into our virtual sink
# WARNING: Firefox must be completely closed prior to running this. 
# If a Firefox process is already running, this will just open a new tab 
# in the existing process and ignore the environment variable.
echo "Launching Firefox..."
PULSE_SINK=WhisperSink firefox &
FIREFOX_PID=$!

# 3. Launch Whisper, forcing its microphone input to listen to the virtual sink's monitor
echo "Starting transcription... (Outputting to transcription_log.txt)"
echo "Press Ctrl+C to stop both transcription and the virtual sink."
PULSE_SOURCE=WhisperSink.monitor ./stream -m models/ggml-base.en.bin -f transcription_log.txt

# (Optional) Kill Firefox when Whisper exits
# kill $FIREFOX_PID

```

***

### How the Magic Works

* **`module-null-sink`**: This creates a dummy audio output device. Anything that plays audio into it makes no physical sound through your speakers.
* **`.monitor`**: Every sink automatically generates a `.monitor` source. This is the "output" side of our virtual cable. By telling Whisper to listen to `WhisperSink.monitor`, it hears exactly what Firefox is playing into the sink.
* **Environment Variables**: By prepending `PULSE_SINK=` to Firefox and `PULSE_SOURCE=` to `./stream`, we override your system's default audio routing for just those specific processes. Your system's main audio and physical microphone remain untouched.

### Handling Already-Running Applications

If you don't want to close Firefox every time you run this, you can dynamically move an existing Firefox audio stream to the virtual sink via bash. It requires parsing `pactl` output. You can replace the Firefox launch line in the script above with something like this:

```bash
# Find the Sink Input ID for Firefox
FIREFOX_INPUT_ID=$(pactl list sink-inputs | grep -B 20 'application.name = "Firefox"' | grep 'Sink Input #' | cut -d '#' -f 2)

if [ -n "$FIREFOX_INPUT_ID" ]; then
    # Move the running Firefox stream to our virtual sink
    pactl move-sink-input "$FIREFOX_INPUT_ID" WhisperSink
    echo "Moved existing Firefox stream to WhisperSink."
else
    echo "Could not find an active Firefox audio stream. Ensure Firefox is playing sound."
fi

```

*(Note: Firefox only creates an audio stream when a tab is actively playing media, so the media must be playing before you run that snippet).*

***

Would you like me to walk you through how to set up a `tail -f` script to parse that output file in real-time, perhaps to trigger desktop notifications or actions when specific keywords are transcribed?
