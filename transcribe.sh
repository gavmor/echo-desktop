#!/bin/bash

# Exit if any command fails
set -e

WHISPER_DIR="whisper.cpp"
MODEL="base.en"
LOG_FILE="transcription_log.txt"
CUSTOM_VOCAB="Mountain View, Foothill College, Smithwick Theatre, Artium, Preact, Vue"

# 1. Setup whisper.cpp if not present
if [ ! -d "$WHISPER_DIR" ]; then
    echo "Cloning whisper.cpp..."
    git clone https://github.com/ggerganov/whisper.cpp.git
fi

cd "$WHISPER_DIR"

if [ ! -f "build/bin/whisper-stream" ]; then
    echo "Building whisper.cpp (including stream tool)..."
    cmake -B build -DWHISPER_SDL2=ON
    cmake --build build --config Release -j
fi

if [ ! -f "build/bin/whisper-stream" ]; then
    echo "Error: whisper-stream binary not found."
    echo "This usually means SDL2 development libraries are missing."
    echo "Please install them using: sudo apt install libsdl2-dev"
    exit 1
fi

if [ ! -f "models/ggml-$MODEL.bin" ]; then
    echo "Downloading $MODEL model..."
    bash ./models/download-ggml-model.sh "$MODEL"
fi

echo "Setting up advanced audio routing..."

# Step A: Get the system's actual default devices to ensure precise routing
DEFAULT_SINK=$(pactl get-default-sink)
DEFAULT_SOURCE=$(pactl get-default-source)

# 2. Create the virtual mixing board (Null Sink)
# This will catch both the mic and the copied application audio
MIX_SINK_ID=$(pactl load-module module-null-sink sink_name=WhisperMixSink sink_properties=device.description="Whisper_Mixer")

# 3. Create the Y-Splitter (Combine Sink)
# This takes audio and sends it to BOTH your actual headphones AND the virtual mixer
COMBINE_SINK_ID=$(pactl load-module module-combine-sink slaves=$DEFAULT_SINK,WhisperMixSink sink_name=SplitSink sink_properties=device.description="Application_Splitter")

# 4. Route the microphone straight into the virtual mixer
# We do NOT send this to the Combine Sink, which is why you won't hear yourself
MIC_LOOPBACK_ID=$(pactl load-module module-loopback source=$DEFAULT_SOURCE sink=WhisperMixSink latency_msec=20)

# Ensure cleanup tears down all virtual modules and exits
cleanup() {
    echo -e "
Cleaning up audio routing..."
    pactl unload-module "$MIC_LOOPBACK_ID" || true
    pactl unload-module "$COMBINE_SINK_ID" || true
    pactl unload-module "$MIX_SINK_ID" || true
    exit
}

trap cleanup INT TERM EXIT

echo "Audio routing complete."
echo "--------------------------------------------------------"
echo "INSTRUCTIONS:"
echo "1. To transcribe an application, run it with: PULSE_SINK=SplitSink <app>"
echo "2. Your default microphone is already being routed to the transcriber."
echo "3. Transcription will be saved to: $(pwd)/$LOG_FILE"
echo "--------------------------------------------------------"

# 6. Optional: Move existing stream if an argument is provided
if [ -n "$1" ]; then
    echo "Attempting to move existing '$1' stream(s) to SplitSink..."
    # Find the Sink Input IDs for the application
    APP_INPUT_IDS=$(pactl list sink-inputs | grep -B 20 "application.name = \"$1\"" | grep "Sink Input #" | cut -d "#" -f 2)
    
    if [ -n "$APP_INPUT_IDS" ]; then
        for ID in $APP_INPUT_IDS; do
            pactl move-sink-input "$ID" SplitSink
            echo "Moved stream #$ID to SplitSink."
        done
    else
        echo "Could not find an active $1 audio stream. Make sure it is playing audio."
    fi
fi

# 5. Launch Whisper, listening only to the virtual mixer
echo "Starting transcription..."
PULSE_SOURCE=WhisperMixSink.monitor ./build/bin/whisper-stream -m "models/ggml-$MODEL.bin" -f "$LOG_FILE"
