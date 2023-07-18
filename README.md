# G.R.E.G.

*Generate a Report of Events, G.R.E.G.*

`index.js` accepts a [craig](https://craig.chat/)-generated zip file as a command-line argument. It does the following:

1. Extracts the archive.
2. Transcribes each audio file using [`whisper.cpp`](https://github.com/ggerganov/whisper.cpp).
3. Consolidates audio files using [`ffmpeg`](https://ffmpeg.org/).
4. Consolidates transcriptions.
5. Fetches additional context from the Juicebox Town Hall Discord chat.
6. Uses an LLM to summarize the meeting.

## Requirements

- [node](https://nodejs.org/)
- [ffmpeg](https://ffmpeg.org/)

## Usage

```bash
# Initialize whisper.cpp submodule
git submodule update --init

# Download medium.en model from HuggingFace
bash ./whisper/models/download-ggml-model.sh medium.en

# Install dependencies
npm install

# Run
node . <path_to_your_zip_file>
```
