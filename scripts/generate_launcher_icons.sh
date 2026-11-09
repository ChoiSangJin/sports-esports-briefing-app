#!/usr/bin/env bash
# Package the approved artwork into Android density resources. Requires ImageMagick 7.
set -euo pipefail
cd "$(dirname "$0")/.."
icon_tmp=$(mktemp -d)
trap 'rm -rf "$icon_tmp"' EXIT
# Ignore nearly transparent generator pixels when locating the emblem, so all
# density variants share the same visual center and safe-area dimensions.
icon_bounds=$(magick assets/branding/ball-foreground.png -alpha extract -threshold 50% -format '%@' info:)
magick assets/branding/ball-foreground.png -crop "$icon_bounds" +repage "$icon_tmp/ball.png"
magick "$icon_tmp/ball.png" -resize 682x682 -gravity center -background '#0B0C10' -extent 1024x1024 -alpha remove -alpha off assets/branding/sports-at-a-glance.png
# A newspaper has corners: its diagonal must fit the 66dp adaptive safe circle.
for spec in mdpi:48:108:48 hdpi:72:162:72 xhdpi:96:216:96 xxhdpi:144:324:144 xxxhdpi:192:432:192; do
  IFS=: read -r density legacy canvas ball <<< "$spec"
  out="android/app/src/main/res/mipmap-$density"
  magick "$icon_tmp/ball.png" -resize "$((legacy * 2 / 3))x$((legacy * 2 / 3))" -gravity center -background '#0B0C10' -extent "${legacy}x${legacy}" -alpha remove -alpha off "$out/ic_launcher.png"
  magick "$icon_tmp/ball.png" -resize "${ball}x${ball}" -gravity center -background none -extent "${canvas}x${canvas}" "$out/ic_launcher_foreground.png"
done
