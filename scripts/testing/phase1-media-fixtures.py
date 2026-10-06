#!/usr/bin/env python3
"""Generate disposable one-second tone/video fixtures for Phase1MediaConversionTests."""

from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise SystemExit("FFmpeg must already be installed; this script does not download it.")
    root = Path(tempfile.mkdtemp(prefix="sotto-phase1-media-"))

    def run(arguments):
        subprocess.run(
            [ffmpeg, "-hide_banner", "-loglevel", "error", "-y", *arguments],
            check=True, timeout=30,
        )

    run(["-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=1",
         "-c:a", "pcm_s16le", str(root / "fixture.wav")])
    for extension, codec in [("m4a", "aac"), ("mp3", "libmp3lame"), ("aac", "aac")]:
        run(["-i", str(root / "fixture.wav"), "-c:a", codec, str(root / f"fixture.{extension}")])
    for extension in ["mp4", "mov"]:
        run(["-f", "lavfi", "-i", "color=c=black:s=32x32:r=10:d=1",
             "-i", str(root / "fixture.wav"), "-c:v", "mpeg4", "-c:a", "aac",
             "-shortest", str(root / f"fixture.{extension}")])
    print(root)


if __name__ == "__main__":
    main()
