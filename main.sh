#!/bin/bash

source .env
if [[ $# -eq 0 ]] ; then
    echo 'Usage: ./main.sh path/to/your/file.zip'
    exit 0
fi

mkdir -p output
echo "Extracting to output/raw-audio/"
unzip -d output/raw-audio $1; echo

echo "Processing audio and writing to output/processed.mp3. This may take a while."
ffmpeg -loglevel 24 \
  $(find output/raw-audio -maxdepth 1 -type f -iname "*.flac" -exec echo -n "-i {} " \;) \
  -filter_complex "amix=inputs=$(ls output/raw-audio/*.flac | wc -l):duration=longest:dropout_transition=2, loudnorm=I=-16:TP=-1.5:LRA=11:print_format=summary" \
  -c:a libmp3lame \
  -b:a 128k output/processed.mp3
echo "Finished processing audio."; echo

echo "Splitting audio into chunks for transcription. Writing to output/chunks/"
mkdir -p output/chunks
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

participants=$(awk -F'[(]' '/Tracks:/{flag=1;next} flag{print $1}' output/raw-audio/info.txt | sed 's/\s*//g' | sed ':a; N; $!ba; s/\n/, /g')
echo "Transcribing audio. This may take a while."
mkdir -p output/transcripts
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

echo "Generating report."
start_time=$(awk '/^Start time:/ { print $3}' output/raw-audio/info.txt | sed 's/\s*//g')
system="I would like you to provide a detailed markdown summary of the following meeting audio transcript. The meeting is the weekly JuiceboxDAO town hall, where Juicebox (an Ethereum funding protocol) is discussed. Please start with a summary that briefly outlines the main topics discussed. Following this, write markdown sections with detailed summaries for each significant topic. Within these sections, I would like bullet points summarizing the most important points raised. The meeting starts at $start_time and the participants are as follows: $participants."
transcript=$(cat output/transcripts/*.txt | sed ':a;N;$!ba;s/\n/\\n/g;s/"/\\"/g')

completion=$(curl https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-3.5-turbo-16k",
    "messages": [
      {"role": "system", "content": "'"$system"'"},
      {"role": "user", "content": "'"$transcript"'"}
    ]
  }')

echo "$completion" > output/raw_res.json
echo "$completion" | jq -r '.choices[0].message.content' > output/report.md
echo "Wrote report to output/report.md and raw response to output/raw_res.json."
