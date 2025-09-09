#!/bin/bash

# Create a simple app icon using built-in tools
# This creates a basic icon with "LL" text

# Get the directory where this script is located and construct the app icon path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICON_DIR="$SCRIPT_DIR/LacyLights.app/Contents/Resources"
TEMP_DIR="/tmp/lacylights_icon"

mkdir -p "$ICON_DIR" "$TEMP_DIR"

# Create a simple SVG icon
cat > "$TEMP_DIR/icon.svg" << 'EOF'
<svg width="512" height="512" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#4A90E2;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#7B68EE;stop-opacity:1" />
    </linearGradient>
  </defs>
  <rect width="512" height="512" rx="90" fill="url(#bg)"/>
  <text x="256" y="320" font-family="Arial, sans-serif" font-size="200" font-weight="bold" text-anchor="middle" fill="white">LL</text>
</svg>
EOF

# Convert SVG to PNG using sips (built into macOS)
# First convert to PDF (macOS can handle SVG to PDF)
qlmanage -t -s 512 -o "$TEMP_DIR" "$TEMP_DIR/icon.svg" >/dev/null 2>&1

# Create iconset directory
ICONSET="$TEMP_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"

# Generate different sizes
for size in 16 32 64 128 256 512; do
    sips -z $size $size "$TEMP_DIR/icon.svg.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>&1
    # Create @2x versions
    size2x=$((size * 2))
    if [ $size -le 256 ]; then
        sips -z $size2x $size2x "$TEMP_DIR/icon.svg.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null 2>&1
    fi
done

# Create the icns file
iconutil -c icns "$ICONSET" -o "$ICON_DIR/AppIcon.icns" 2>/dev/null

# Clean up
rm -rf "$TEMP_DIR"

echo "App icon created successfully"