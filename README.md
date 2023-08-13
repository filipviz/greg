# G.R.E.G.

*Generate a Report of Events, G.R.E.G.*

`main.sh` accepts a [craig](https://craig.chat/)-generated zip file as a command-line argument. It does the following:

1. Extracts the archive.
2. Consolidates audio files using [`ffmpeg`](https://ffmpeg.org/).
3. Breaks the audio file into segments, and transcribes them using [OpenAI's Whisper](https://openai.com/research/whisper).
4. Fetches additional context from the Juicebox Town Hall Discord chat and agenda.
5. Uses [`gpt-3.5-turbo-16k`](https://platform.openai.com/docs/models/gpt-3-5) to summarize the meeting.

## Requirements

- [`ffmpeg`](https://ffmpeg.org/)
- [`jq`](https://jqlang.github.io/jq/download/)

## Usage

```bash
# Create a .env file and enter your OpenAI API key and Discord bot Token
cp .example.env .env

# Make the script executable
sudo chmod +x main.sh

# Run the script
bash main.sh your-craig-file.zip
```

## Notes

```bash
# To import from a discordchatexporter-cli .csv
messages=$(awk -F ',' '{if(NR>1) printf substr($2, 2, length($2)-2) ": " substr($4, 2, length($4)-2) " # "}' ./messages.csv | tr -d '\"' | tr -d "\n")
# Add to system:
system+=" Please incorporate links and context from the following messages from the meeting's realtime chat: $messages"
```
