# Third-Party Notices, Credits & Source Code Disclosure (GPLv3 Section 6)

## 1. Upstream ZXTune (`zxtune123` CLI & Format Decoding Engine)
- **Project**: ZXTune (revision r5112)
- **Author**: Vitamin/CAIG (Andrey)
- **License**: GNU General Public License v3.0 (GPL-3.0)
- **Official Homepage**: https://zxtune.bitbucket.io/
- **Corresponding Source Code**:
  - https://github.com/vitamin-caig/zxtune
  - https://bitbucket.org/zxtune/zxtune

In accordance with Section 6 of the GNU General Public License v3.0, the complete source code for the `zxtune123` binary bundled in `Bin/x86_64-linux/zxtune123` is available at no charge from the upstream repositories listed above.

## 2. Third-Party Sound Emulation & Codec Libraries in `zxtune123`
`zxtune123` incorporates open-source sound chip emulation and compression libraries distributed under GPL-compatible licenses:
- **libsidplayfp / reSIDfp**: Copyright (C) Simon White, Antti S. Lankila, Leandro Nini, VICE Project (GPLv2+)
- **Game_Music_Emu / snes_spc**: Copyright (C) Shay Green (LGPLv2.1+)
- **libxmp**: Copyright (C) Claudio Matsuoka, Hipolito Carraro Jr (MIT / LGPLv2.1+)
- **libopenmpt**: Copyright (C) OpenMPT Developers (BSD-3-Clause)
- **libvgm / vgmstream**: Copyright (C) Valley Bell, hcs, et al. (ISC / MIT / GPLv2+)
- **Highly Experimental / Highly Theoretical / lazyusf2 / vio2sf / mGBA**: Copyright (C) Neill Corlett, Christopher Snowhill, Jeffrey Pfau (GPLv2+ / MPL-2.0)
- **ASAP (Another Slight Atari Player)**: Copyright (C) Piotr Fusik (GPLv2+)
- **HVL2WAV (HivelyTracker / AHX)**: Copyright (C) Xeron / IRIS (BSD / Public Domain)
- **libFLAC / libogg / libvorbis**: Copyright (C) Xiph.Org Foundation (BSD-3-Clause)
- **LAME MP3 Encoder**: Copyright (C) The LAME Project (LGPLv2+)
- **zlib / LZMA SDK (7-Zip)**: Copyright (C) Jean-loup Gailly, Mark Adler, Igor Pavlov (Zlib / Public Domain)
- **UnRAR decompression library**: Copyright (C) Alexander Roshal (UnRAR license; used strictly for archive decompression, never to recreate the RAR compression algorithm)

## 3. Online Catalogues & Cover Art Disclaimer
- This plugin does **not** bundle, host, or redistribute any copyrighted music tracks, ROMs, BIOS images, or cover art.
- All online music catalogues (`ZXTunes.com`, `ZX-Art.ee`, `The Mod Archive`, `ModLand`, `HVSC`, `ASMA`, `AYGOR`, `JoshW`, `AMP`, `Aminet`, `Scene.org`, `VGMRips`, `Khinsider`, `OverClocked ReMix`) and online boxart thumbnails (`thumbnails.libretro.com`) are independent third-party services accessed on-demand directly by the user's server at the user's initiation, mirroring the virtual filesystem (`app.zxtune.fs.*`) of the upstream ZXTune application.
- Users are responsible for complying with the terms of service of any third-party online catalogue they choose to access. Online cover art lookup for local files can be disabled at any time in **Settings -> Advanced -> Media Server -> ZXTune -> Automatic Online Cover Art for Local Games -> Offline Only**.
