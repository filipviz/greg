#!/bin/bash

. .env
if [ $# -eq 0 ]; then
    echo 'Usage: ./main.sh path/to/your/file.zip'
    exit 0
fi

mkdir output
echo "Extracting to output/raw-audio/"
unzip -d output/raw-audio $1; echo

echo "Processing audio and writing to output/processed.mp3. This may take a while."
ffmpeg -loglevel 24 \
  $(find output/raw-audio -maxdepth 1 -type f -name "*.flac" -exec echo -n "-i {} " \;) \
  -filter_complex "amix=inputs=$(ls output/raw-audio/*.flac | wc -l):duration=longest:dropout_transition=2, loudnorm=I=-16:TP=-1.5:LRA=11:print_format=summary" \
  -c:a libmp3lame \
  -b:a 128k output/processed.mp3
echo "Finished processing audio."; echo

echo "Splitting audio into chunks for transcription. Writing to output/chunks/"
mkdir output/chunks
index=0
duration=1536 # ~24 MB mp3 @ 128 kb/s
total_duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 output/processed.mp3)

while [ $(awk -v a="$duration" -v b="$index" 'BEGIN {print (a * b < '$total_duration') ? "1" : "0"}') -eq 1 ]; do
  start_time=$(awk -v a="$duration" -v b="$index" 'BEGIN {print (a * b)}')
  echo "Encoding chunk $index, starting at t:$start_time."
  ( ffmpeg -loglevel 24 \
    -i output/processed.mp3 \
    -vn \
    -acodec copy \
    -ss "$start_time" \
    -t "$duration" \
    "output/chunks/audio_chunk_${index}.mp3" ) &
  index=$((index+1))
done; wait
echo "Chunk encoding completed."; echo

participants=$(awk -F'[(]' '/Tracks:/{flag=1;next} flag{print $1}' output/raw-audio/info.txt | awk '{$1=$1} {s=s (s?", ":"") $0} END{print s}')
echo "Transcribing audio. This may take a while."
mkdir output/transcripts
index=0
for f in ./output/chunks/*; do
  echo "Transcribing $f"
  ( curl https://api.openai.com/v1/audio/transcriptions \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: multipart/form-data" \
    -F file="@$f" \
    -F model="whisper-1" \
    -F response_format=text \
    -F prompt="Juicebox, JuiceboxDAO, DAO, Peel, juicebox.money, $participants." > output/transcripts/transcript_${index}.txt 2>/dev/null 
    echo "Finished transcribing $f"
  ) &
  index=$((index+1))
done; wait
echo "All transcribing completed."; echo

start_time=$(awk '/^Start time:/ { print $3}' output/raw-audio/info.txt | sed 's/\s*//g')
echo "Fetching Discord messages from town-hall-chat."
CHAT_START_TIME=$(date -Ins -ud "$start_time - 3 hours")
BASE_URL="https://discord.com/api/v10"
TOWNHALL_CHANNEL_ID="1009220977906950234"

message_id="latest"
while true; do
    if [ "$message_id" = "latest" ]; then
        url="${BASE_URL}/channels/${TOWNHALL_CHANNEL_ID}/messages?limit=100"
    else
        url="${BASE_URL}/channels/${TOWNHALL_CHANNEL_ID}/messages?before=${message_id}&limit=100"
    fi

    response=$(curl -s -X GET "${url}" \
        -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
        -H "Content-Type: application/json")

    echo "$response" | jq -r '[.[] | select(.timestamp >= "'$CHAT_START_TIME'")] | reverse | .[] | .author.username + ": " + .content' >> output/chat-messages.txt

    last_timestamp=$(echo "$response" | jq -r '.[-1].timestamp')
    if [[ "$last_timestamp" < "$CHAT_START_TIME" ]]; then
      break
    fi
    message_id=$(echo "$response" | jq -r '.[-1].id')
    sleep 1
done
echo "town-hall-chat messages written to output/chat-messages.txt"

echo "Fetching Discord messages from the Town Hall Agenda."
AGENDAS_CHANNEL_ID="876226014001377330"
response=$(curl -s -X GET "${BASE_URL}/channels/${AGENDAS_CHANNEL_ID}/messages?limit=100" \
  -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
  -H "Content-Type: application/json")
thread_starter=$(echo "${response}" | jq -r --arg TOWNHALL_TIMESTAMP "$start_time" '.[] | select(.type == 18 and .thread.thread_metadata.create_timestamp != null and .thread.thread_metadata.create_timestamp < $TOWNHALL_TIMESTAMP) | .id' | head -1)

# Assuming there will be fewer than 100 messages in the agenda thread.
response=$(curl -s -X GET "${BASE_URL}/channels/${thread_starter}/messages?limit=100" \
    -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
    -H "Content-Type: application/json")
echo "$response" | jq -r '.[] | "\(.author.username): \(.content)"' | tac > output/agenda-messages.txt
echo "Town Hall Agenda messages written to output/agenda-messages.txt"; echo

echo "Generating report."
agenda=$(cat output/agenda-messages.txt | tr -d '\"' | tr -d "\n")
chat=$(cat output/chat-messages.txt | tr -d '\"' | tr -d "\n")
system="I would like you to provide a detailed markdown summary of the following meeting audio transcript. The meeting is the weekly JuiceboxDAO town hall, where Juicebox (an Ethereum funding protocol) is discussed. JBM stands for https://juicebox.money. Please start with a summary that briefly outlines the main topics discussed. Following this, write markdown sections with detailed summaries for each significant topic. Within these sections, I would like bullet points summarizing the most important points raised. The meeting starts at $start_time and the participants are as follows: $participants. ### Here are messages pertaining to the meeting agenda: $agenda. ### Incorporate the links and context from these text chat messages in your report: $chat"
transcript=$(cat output/transcripts/*.txt | tr -d '\"' | tr -d "\n")

response=$(curl https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-3.5-turbo-16k",
    "messages": [
      {"role": "system", "content": "'"$system"'"},
      {"role": "user", "content": "Here is the transcript: '"$transcript"'"}
    ]
  }')

echo "$response" > output/raw_res.json
echo "$response" | jq -r '.choices[0].message.content' > output/report.md
echo "Wrote report to output/report.md and raw response to output/raw_res.json."
