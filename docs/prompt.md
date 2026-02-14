To get Whisper to consistently spell proper nouns, industry jargon, or specific names correctly, you can use the `--prompt` (or `-p`) flag. This feeds an "initial prompt" into the model's context window before it starts listening. Whisper uses this text to establish context and bias its output toward the spellings you provide.

The most effective way to format this prompt is as a comma-separated list of correctly capitalized nouns.

Here is how to integrate that into your existing Bash script. I have added a `CUSTOM_VOCAB` variable at the top so you can easily update your list of nouns without having to hunt through the routing commands.

### The Script with Custom Vocabulary

```bash
#!/bin/bash

# Exit if any command fails
set -e

# Define your proper nouns and custom vocabulary here.
# A comma-separated list with proper capitalization works best.
CUSTOM_VOCAB="Mountain View, Foothill College, Smithwick Theatre, Artium, Preact, Vue"

echo "Setting up advanced audio routing..."

DEFAULT_SINK=$(pactl get-default-sink)
DEFAULT_SOURCE=$(pactl get-default-source)

# 1. Create the virtual mixing board (Null Sink)
MIX_SINK_ID=$(pactl load-module module-null-sink sink_name=WhisperMixSink sink_properties=device.description="Whisper_Mixer")

# 2. Create the Y-Splitter (Combine Sink)
COMBINE_SINK_ID=$(pactl load-module module-combine-sink sink_name=SplitSink slaves=$DEFAULT_SINK,WhisperMixSink sink_properties=device.description="Firefox_Splitter")

# 3. Route the microphone straight into the virtual mixer
MIC_LOOPBACK_ID=$(pactl load-module module-loopback source=$DEFAULT_SOURCE sink=WhisperMixSink latency_msec=20)

# Ensure cleanup tears down all three virtual modules in reverse order
trap 'echo -e "\nCleaning up audio routing..."; pactl unload-module $MIC_LOOPBACK_ID; pactl unload-module $COMBINE_SINK_ID; pactl unload-module $MIX_SINK_ID; exit' INT TERM EXIT

# 4. Launch Firefox, forcing its audio into the Y-Splitter
echo "Launching Firefox..."
PULSE_SINK=SplitSink firefox &

# 5. Launch Whisper, passing the custom vocabulary into the initial prompt
echo "Starting transcription... (Outputting to transcription_log.txt)"
echo "Press Ctrl+C to stop transcription and clean up."
PULSE_SOURCE=WhisperMixSink.monitor ./stream -m models/ggml-base.en.bin --prompt "$CUSTOM_VOCAB" -f transcription_log.txt

```

### Tips for the Whisper Prompt

* **Punctuation Matters:** Whisper infers formatting from the prompt. If you provide a comma-separated list, it learns the words without assuming they form a complete sentence. If you write a full sentence with a period at the end, it might bias the model to try and end its own transcribed sentences prematurely.
* **Keep it Concise:** The prompt shares space with the model's rolling context window. If you make the list too long (over ~200 tokens), it will push out the actual audio context faster. Stick to the most critical proper nouns for your current session.
* **Acoustic Similarities:** If a word sounds like a common word but is spelled differently, the prompt is highly effective at forcing the correct variant (e.g., ensuring it outputs "Vue" instead of "view").

Would you like me to show you how to add flags to output this transcription with timestamps, so it writes directly to a standard `.srt` or `.vtt` subtitle file instead of a plain text log?
