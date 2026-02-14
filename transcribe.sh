#!/bin/bash

# Exit if any command fails
set -e

ROOT_DIR=$(pwd)
WHISPER_DIR="whisper.cpp"
MODEL="large-v3-turbo"
LOG_FILE="$ROOT_DIR/transcription_log.txt"
CUSTOM_VOCAB="Mountain View, Foothill College, Smithwick Theatre, Artium, Preact, Vue"

# 1. Setup whisper.cpp if not present
if [ ! -d "$WHISPER_DIR" ]; then
    echo "Cloning whisper.cpp..."
    git clone https://github.com/ggerganov/whisper.cpp.git
fi

cd "$WHISPER_DIR"

if [ ! -f "build/bin/whisper-stream" ]; then
    echo "Building whisper.cpp (including stream tool) with CUDA support..."
    cmake -B build -DWHISPER_SDL2=ON -DGGML_CUDA=ON
    cmake --build build --config Release -j$(nproc)
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

# Step B: Ensure everything is unmuted and at 100% volume
echo "Optimizing volume levels..."
sleep 1
pactl set-sink-volume WhisperMixSink 100%
pactl set-sink-mute WhisperMixSink false
pactl set-sink-volume SplitSink 100%
pactl set-sink-mute SplitSink false

# Ensure cleanup tears down all virtual modules and exits
cleanup() {
    echo -e "
Cleaning up audio routing and processes..."
    # Kill any child processes of this script (like whisper-stream)
    jobs -p | xargs -r kill -9 2>/dev/null || true
    
    # Restore default source if we changed it
    if [ -n "$OLD_DEFAULT_SOURCE" ]; then
        pactl set-default-source "$OLD_DEFAULT_SOURCE" || true
    fi
    pactl unload-module "$MIC_LOOPBACK_ID" || true
    pactl unload-module "$COMBINE_SINK_ID" || true
    pactl unload-module "$MIX_SINK_ID" || true
    exit
}

trap cleanup INT TERM EXIT

# Set the virtual mixer as the default source for this session
# This ensures SDL and other apps pick it up without complex ID mapping
OLD_DEFAULT_SOURCE=$(pactl get-default-source)
pactl set-default-source WhisperMixSink.monitor

echo "Audio routing complete."
echo "--------------------------------------------------------"
echo "INSTRUCTIONS:"
echo "1. To transcribe an application, run it with: PULSE_SINK=SplitSink <app>"
echo "2. Your default microphone is already being routed to the transcriber."
echo "3. Transcription will be saved to: $LOG_FILE"
echo "--------------------------------------------------------"

# 6. Optional: Move existing stream if an argument is provided
if [ -n "$1" ]; then
    echo "Searching for '$1' audio streams..."
    # Get all sink-input IDs that match the application name or process name
    APP_INPUT_IDS=$(pactl list sink-inputs | grep -B 20 -E "application.name = \"$1\"|node.name = \"$1\"|media.name = \"$1\"" | grep "Sink Input #" | cut -d "#" -f 2)
    
    if [ -n "$APP_INPUT_IDS" ]; then
        for ID in $APP_INPUT_IDS; do
            echo "Moving stream #$ID to SplitSink..."
            pactl move-sink-input "$ID" SplitSink
        done
        echo "Successfully redirected '$1' to the transcriber."
        # If this was called as a helper, exit so we don't start a second whisper process
        if [ "$0" = "./transcribe.sh" ] || [ "$0" = "transcribe.sh" ]; then
            exit 0
        fi
    else
        echo "Could not find an active '$1' stream. Try using the exact name from 'pactl list sink-inputs'."
        exit 1
    fi
fi

# 5. Launch Whisper, listening only to the virtual mixer
echo "Starting transcription (GPU Accelerated)..."
echo -e "\n--- Session started at $(date) ---" >> "$LOG_FILE"
# Force SDL to use PulseAudio and follow the default source we just set
export SDL_AUDIO_DRIVER=pulseaudio
# whisper-stream uses GPU by default if built with CUDA; we force device 0 via env
CUDA_VISIBLE_DEVICES=0 stdbuf -oL ./build/bin/whisper-stream -m "models/ggml-$MODEL.bin" -t 8 2>&1 | tee -a "$LOG_FILE"
