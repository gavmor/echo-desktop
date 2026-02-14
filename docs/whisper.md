Streaming specific application audio (like Firefox) directly into a live-transcription engine is a perfect use case for modern Linux audio subsystems. Because of **PipeWire** (the default on most modern distros), we can treat audio as a graph and easily patch application outputs directly into other applications' inputs without complex command-line piping.

To do this efficiently, I highly recommend using **`whisper.cpp`** rather than the default OpenAI Python library. It is a highly optimized C/C++ port of Whisper that includes a built-in `./stream` tool specifically designed to capture live audio from your system's sound server.

Here is the step-by-step guide to setting this up.

### 1. Install Dependencies

You will need a C++ compiler and the SDL2 development libraries, which `whisper.cpp` relies on to capture live audio natively. You will also want a visual PipeWire patchbay like `qpwgraph` to easily route the audio.

On Ubuntu/Debian:

```bash
sudo apt update
sudo apt install build-essential git libsdl2-dev qpwgraph

```

*(If you are on Arch, install `sdl2` and `qpwgraph`. On Fedora, install `SDL2-devel` and `qpwgraph`)*.

***

### 2. Build the Whisper Streamer

Clone the repository and compile the live stream tool.

```bash
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
make stream

```

Next, download a lightweight model. For live transcription, the `base.en` or `small.en` models strike the best balance between speed and accuracy on standard hardware:

```bash
bash ./models/download-ggml-model.sh base.en

```

***

### 3. Start the Transcription Engine

Run the `stream` executable, point it to your model, and use the `-f` flag to tell it to continuously append the output to a text file on your disk.

```bash
./stream -m models/ggml-base.en.bin -f ~/desktop_transcription.txt

```

*Note: As soon as you hit enter, Whisper will begin listening to your system's default recording device (usually your physical microphone). We will change what it's listening to in the next step.*

***

### 4. Route Firefox Audio to Whisper

This is where the Linux magic happens.

1. Leave the `./stream` command running in your terminal.
2. Open **Firefox** and play a video or audio track. (The audio node won't show up in the graph until the browser is actively outputting sound).
3. Open **`qpwgraph`**.
4. Look at the visual graph. You will see a block for **Firefox** on the left (Playback/Output) and a block representing your **`stream`** application (Capture/Input) on the right.
5. **Draw a wire:** Click and drag a line from Firefox's output ports directly into the `stream` application's input ports.
6. **Disconnect your mic:** If you see a wire connecting your physical microphone to the `stream` node, click that wire and delete it. This ensures Whisper *only* hears Firefox, and doesn't transcribe your typing or breathing.

Everything Firefox plays will now be routed directly into the Whisper model, transcribed in near real-time, and saved directly to `~/desktop_transcription.txt`.

***

Would you like me to walk you through how to pass specific flags to the `./stream` tool to adjust the context window, change how often it commits text to the file, or utilize a GPU for even faster processing?
