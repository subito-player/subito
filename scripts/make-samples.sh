#!/usr/bin/env bash
# Test clips, logos, a movie and a concert for trying the app without real footage.
set -euo pipefail

out="${1:-build/samples}"
font=/System/Library/Fonts/Supplemental/Arial.ttf
ff() {
    if command -v ffmpeg >/dev/null; then ffmpeg -hide_banner -loglevel error -y "$@"
    else nix shell nixpkgs#ffmpeg --command ffmpeg -hide_banner -loglevel error -y "$@"; fi
}
txt() { echo "drawtext=fontfile=$font:fontcolor=white:fontsize=$2:x=(w-tw)/2:y=$3:text='$1'"; }
tc() { echo "drawtext=fontfile=$font:fontcolor=white:fontsize=56:box=1:boxcolor=black@0.6:x=(w-tw)/2:y=h-140:text='%{pts\:hms}  f%{n}'"; }

mkdir -p "$out/clips" "$out/logos"
enc=(-c:v libx264 -preset veryfast -pix_fmt yuv420p -movflags +faststart)

# name, seconds, lavfi source, fps, extra video filter, label
clip() {
    local name=$1 dur=$2 src=$3 fps=$4 vf=$5 label=$6
    local fade="fade=t=out:st=$((dur - 1)):d=1"
    ff -f lavfi -i "$src:d=$dur:r=$fps" -f lavfi -i "sine=frequency=440:d=$dur" \
        -vf "$vf,$(txt "$label" 64 80),$(tc),$fade" -r "$fps" -shortest "${enc[@]}" -c:a aac \
        "$out/clips/$name.mp4"
}

clip 00_title 15 "color=c=black:s=1920x1080" 24000/1001 "null" "TITLE (pause here, wait for conductor)"
clip 01_letterboxed 40 "testsrc2=s=1920x800" 24000/1001 "pad=1920:1080:0:140:black" "01 1080p 23.976 letterboxed 2.4 to 1"
clip 02_smpte 30 "smptehdbars=s=1920x1080" 24000/1001 "null" "02 1080p 23.976 SMPTE bars"
clip 03_other_source 20 "testsrc=s=1280x720" 25 "null" "03 720p 25 fps (other creator)"
clip 04_four_by_three 15 "testsrc2=s=1440x1080" 30000/1001 "null" "04 4 by 3, 29.97 fps (pillarbox)"

ff -f lavfi -i "color=c=black:s=1920x1080:d=1" -vf "$(txt "EXAMPLE ORCHESTRA" 120 '(h-th)/2')" -frames:v 1 "$out/logos/orchestra.png"
ff -f lavfi -i "color=c=black:s=1920x1080:d=1" -vf "$(txt "SPRING GALA 2026" 120 '(h-th)/2')" -frames:v 1 "$out/logos/event.png"

cat > "$out/clips/clips.movie.json" <<'EOF'
{ "format": 1, "title": "Sample film",
  "items": [
    { "type": "clip", "file": "00_title.mp4", "planned_end_s": 10, "tail_s": 5 },
    { "type": "clip", "file": "01_letterboxed.mp4", "planned_end_s": 25, "tail_s": 15 },
    { "type": "black" },
    { "type": "clip", "file": "02_smpte.mp4", "planned_end_s": 20, "tail_s": 10 },
    { "type": "clip", "file": "03_other_source.mp4" },
    { "type": "clip", "file": "04_four_by_three.mp4" } ] }
EOF

cat > "$out/samples.concert.json" <<'EOF'
{ "format": 1, "title": "Sample concert", "logos": ["logos/orchestra.png", "logos/event.png"],
  "items": [
    { "type": "black" },
    { "type": "movie", "file": "clips/clips.movie.json" },
    { "type": "break", "minutes": 1, "countdown": true, "text": "Szünet" },
    { "type": "logo", "logo": 1 } ] }
EOF

echo "samples in $out: $(ls "$out/clips" | tr '\n' ' ')"
