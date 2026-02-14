To merge your USB microphone into the same transcription stream, we need to mix two separate audio sources (Firefox's output and your microphone's input) into our single virtual cable (`WhisperSink`).

In the PulseAudio/PipeWire ecosystem, we achieve this using **`module-loopback`**. This module takes audio from a source (your microphone) and continuously "plays" it back into a sink (our virtual cable). Because our `WhisperSink` acts as a mixer, it will seamlessly combine your mic audio with the Firefox audio, and `whisper.cpp` will transcribe both simultaneously.

Here is the updated, fully automated Bash script.

### The Updated Automation Script

```bash
#!/bin/bash

# Exit if any command fails
set -e

# 1. Create the virtual audio mixing cable
echo "Creating virtual audio cable (WhisperSink)..."
SINK_ID=$(pactl load-module module-null-sink sink_name=WhisperSink sink_properties=device.description="Whisper_Routing")

# 2. Loopback the microphone into the virtual cable
# Using @DEFAULT_SOURCE@ grabs whatever mic is currently set as default in your system settings.
# We set a low latency so your voice syncs well with the system audio.
echo "Routing microphone into WhisperSink..."
LOOPBACK_ID=$(pactl load-module module-loopback source=@DEFAULT_SOURCE@ sink=WhisperSink latency_msec=20)

# Ensure cleanup removes both the sink and the loopback module
trap 'echo -e "\nCleaning up audio routing..."; pactl unload-module $SINK_ID; pactl unload-module $LOOPBACK_ID; exit' INT TERM EXIT

# 3. Launch Firefox, forcing its audio into the virtual sink
echo "Launching Firefox..."
PULSE_SINK=WhisperSink firefox &

# 4. Launch Whisper, listening to the combined monitor of the virtual sink
echo "Starting transcription... (Outputting to transcription_log.txt)"
echo "Press Ctrl+C to stop transcription and clean up."
PULSE_SOURCE=WhisperSink.monitor ./stream -m models/ggml-base.en.bin -f transcription_log.txt

```

### Specifying a Specific USB Microphone

The script above uses `@DEFAULT_SOURCE@`, which is usually the easiest approach if your system already defaults to your USB mic. However, if you want to hardcode the script to *always* use that specific USB microphone regardless of your system defaults, follow these steps:

1. Run `pactl list short sources` in your terminal.
2. Look through the output for your USB microphone. You are looking for a name string (the second column), which usually looks something like `alsa_input.usb-Blue_Microphones_Yeti...`.
3. Replace `@DEFAULT_SOURCE@` in the script with that exact string:

```bash
LOOPBACK_ID=$(pactl load-module module-loopback source=alsa_input.usb-Blue_Microphones... sink=WhisperSink latency_msec=20)

```

***A quick note on monitoring:** Because Firefox is outputting directly to the `WhisperSink`, you will not hear Firefox through your own headphones. Whisper will hear it, but you won't.* Would you like me to add one more `module-loopback` command to the script so that a copy of the combined audio is routed back to your headphones, allowing you to actually hear the Firefox stream while you talk?
