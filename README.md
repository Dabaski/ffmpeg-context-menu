# FFmpeg Context Menu Converter

Right-click Windows context menu integration for converting video and audio files with FFmpeg.

## Requirements

- Windows 10/11
- FFmpeg installed and in PATH
- PowerShell 5.1+

## Installation

1. Open PowerShell as Administrator (or regular user for HKCU)
2. Run:
   ```powershell
   .\install.ps1
   ```

## Uninstallation

```powershell
.\install.ps1 -Uninstall
```

## Usage

1. Right-click any supported media file in Windows Explorer
2. Select "Convert with FFmpeg"
3. Choose target format from the dialog
4. Wait for conversion to complete

## Supported Formats

**Video Input:** MP4, MKV, AVI, MOV, WebM, FLV, WMV, M4V

**Audio Input:** MP3, WAV, FLAC, AAC, OGG, M4A, WMA, OPUS

**Output Formats:**
| Format | Codec/Settings |
|--------|----------------|
| MP4 | H.264, CRF 23, AAC 192k |
| MKV | H.264, CRF 23, AAC 192k |
| WebM | VP9, CRF 30, Opus 128k |
| AVI | MPEG4, MP3 192k |
| MOV | H.264, AAC 192k |
| GIF | 15fps, 480px width |
| MP3 | LAME VBR Q2 |
| WAV | PCM 16-bit |
| FLAC | Lossless |
| OGG | Vorbis Q5 |
| OPUS | 128k |
| AAC | 192k |

## Command Line Usage

```powershell
# With format dialog
.\convert-media.ps1 "C:\path\to\video.mp4"

# Direct conversion
.\convert-media.ps1 "C:\path\to\video.mp4" -TargetFormat mkv

# Custom output directory
.\convert-media.ps1 "C:\path\to\video.mp4" -TargetFormat mp3 -OutputDir "D:\output"
```

## Running Tests

```powershell
.\tests\Test-ConvertMedia.ps1

# Skip integration tests (no actual conversions)
.\tests\Test-ConvertMedia.ps1 -SkipIntegration
```

## File Structure

```
ffmpeg-context-menu/
├── convert-media.ps1    # Main conversion script
├── install.ps1          # Registry installer/uninstaller
├── README.md
└── tests/
    └── Test-ConvertMedia.ps1
```
