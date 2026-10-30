#!/usr/bin/env bash
# Package the approved artwork into Android density resources. Requires ImageMagick 7.
set -euo pipefail
cd "$(dirname "$0")/.."
icon_tmp=$(mktemp -d)
trap 'rm -rf "$icon_tmp"' EXIT
# Ignore nearly transparent generator pixels when locating the ball, so all
# density variants share the same visual center and safe-area dimensions.
icon_bounds=$(magick assets/branding/ball-foreground.png -alpha extract -threshold 50% -format '%@' info:)
magick assets/branding/ball-foreground.png -crop "$icon_bounds" +repage "$icon_tmp/ball.png"
magick "$icon_tmp/ball.png" -resize 682x682 -gravity center -background '#0B0C10' -extent 1024x1024 -alpha remove -alpha off assets/branding/sports-at-a-glance.png
for spec in mdpi:48:108:56 hdpi:72:162:84 xhdpi:96:216:112 xxhdpi:144:324:168 xxxhdpi:192:432:224; do
  IFS=: read -r density legacy canvas ball <<< "$spec"
  out="android/app/src/main/res/mipmap-$density"
  magick "$icon_tmp/ball.png" -resize "$((legacy * 2 / 3))x$((legacy * 2 / 3))" -gravity center -background '#0B0C10' -extent "${legacy}x${legacy}" -alpha remove -alpha off "$out/ic_launcher.png"
  magick "$icon_tmp/ball.png" -resize "${ball}x${ball}" -gravity center -background none -extent "${canvas}x${canvas}" "$out/ic_launcher_foreground.png"
done
