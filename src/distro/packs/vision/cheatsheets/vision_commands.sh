# ==========================================
# VISION & OCR CHEATSHEET
# requires: tesseract
# ==========================================
# The three tools the `vision` pack brings, and the commands one actually
# reaches for. The pack is installed from Windows (`.\wsl.ps1 add_pack`) and
# removed the same way; the page is packs/vision/docs/vision.md.
# Offered only while the tools are installed - the header above is what hides
# the sheet when they were removed by hand.

# --- 1. OCR (tesseract) ---
tesseract image.png -                          # Read the text of an image, to stdout
tesseract image.png out -l fra                 # ... in French (out.txt)
tesseract image.png out pdf                    # ... as a searchable PDF (out.pdf)
tesseract --list-langs                         # Which languages are installed
tesseract page.jpg out --psm 6                 # ... assuming one uniform block of text

# --- 2. IMAGES (imagemagick) ---
identify image.png                             # Size, format, colour depth
convert image.png image.jpg                    # Convert
convert image.png -resize 50% small.png        # Resize, in percent
convert image.png -resize 800x600 small.jpg    # ... to a box (keeps the ratio)
convert image.png -strip -quality 85 small.jpg # Drop metadata, set JPEG quality
mogrify -resize 800x *.jpg                     # Resize every JPEG of a folder, in place
convert -append top.png bottom.png joined.png  # Stack images vertically

# --- 3. AUDIO & VIDEO (ffmpeg) ---
ffprobe video.mp4                              # What is inside the file
ffmpeg -i video.mp4 -vf scale=1280:-1 out.mp4  # Resize (width set, height follows)
ffmpeg -i video.mp4 -vn -c:a copy audio.m4a    # Extract the audio, without re-encoding
ffmpeg -i video.mp4 -r 1 frame-%03d.png        # One image per second
ffmpeg -i audio.wav -b:a 192k audio.mp3        # Convert audio, with a bitrate
