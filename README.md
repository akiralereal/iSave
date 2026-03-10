# iSave

**English** | [中文](README.zh.md)

<p align="center"><a href="https://ifansclub.com/"><img src="iSave/Resources/ifansclub.svg" alt="iFansClub" width="180" /></a></p>
<p align="center"><strong>Want more updates? Visit iFans Club:</strong></p>
<p align="center"><a href="https://ifansclub.com/"><img alt="Visit iFans Club" src="https://img.shields.io/badge/VISIT-IFANSCLUB-57F2D2?style=for-the-badge&labelColor=1CCBA8&color=57F2D2" /></a></p>
<p align="center"><a href="https://ifansclub.com/"><code>https://ifansclub.com/</code></a></p>

A macOS video & picture downloader that supports YouTube, Instagram, TikTok, and 1000+ other sites.

Powered by [yt-dlp](https://github.com/yt-dlp/yt-dlp), [ffmpeg](https://ffmpeg.org/), and [gallery-dl](https://github.com/mikf/gallery-dl) — bundled and ready to use out of the box.

![iSave Screenshot](iSave/Resources/isave.jpg)

---

## Features

- **Multi-platform**: YouTube, Instagram, TikTok, Bilibili, and 1000+ sites supported by yt-dlp
- **Flexible formats**: Export as MP4, MKV, MP3, or M4A
- **Quality options**: Choose video resolution and audio bitrate
- **Concurrent downloads**: Set 1 / 2 / 3 / 5 simultaneous tasks
- **Cookie support**: Automatically reads cookies from Safari, Chrome, etc. for login-required content
- **Sleep prevention**: Keeps the system awake during downloads
- **Auto update check**: Built-in version checker

## Requirements

- macOS 12.4 or later
- Apple Silicon or Intel

## Download

Visit the [Releases](https://github.com/akiralereal/iSave/releases) page to download the latest `.dmg`.

## Build from Source

```bash
git clone https://github.com/akiralereal/iSave.git
cd iSave
open iSave.xcodeproj
```

In Xcode:
1. **Signing & Capabilities** → select your own Apple Developer account
2. **Product → Run** (⌘R)

> Xcode will automatically resolve SPM dependencies on first build.

## Contributing

Issues and Pull Requests are welcome.

## License

[GPL v3](LICENSE)
