# ZXTune for Daphile & Lyrion Music Server (LMS)

Complete port of **ZXTune (`r5112`)** for **Daphile** and **Lyrion Music Server (Logitech Media Server)** on `x86_64-linux`.

## Features
- **120+ Chiptune, Tracker & Video Game Music Formats**:
  - **ZX Spectrum / Amstrad / Sam Coupe**: `AY`, `PT1`, `PT2`, `PT3`, `STC`, `STP`, `ASC`, `PSC`, `SQT`, `VTX`, `YM`, `PSG`, `TS`, `TFD`, `TFC`, `COP`, `ET1`
  - **Commodore 64**: `SID`, `PSID`, `RSID`
  - **Nintendo Consoles & Handhelds**: `NSF`, `NSFE` (NES), `SPC`, `RSN` (SNES), `GBS` (Game Boy), `GSF` (GBA), `2SF` (DS), `3SF` (3DS), `USF` (N64)
  - **Sega Consoles**: `VGM`, `VGZ`, `GYM` (Master System / Mega Drive / Genesis), `SSF` (Saturn), `DSF` (Dreamcast)
  - **Sony PlayStation**: `PSF`, `MINIPSF` (PS1), `PSF2`, `MINIPSF2` (PS2)
  - **Atari / MSX / PC Engine / NEC**: `SAP` (Atari XL/XE), `SNDH` (Atari ST), `KSS` (MSX/SMS), `HES` (PC Engine / TurboGrafx-16), `S98` (PC-88/PC-98)
  - **Amiga & PC Tracker Modules**: `MOD`, `XM`, `IT`, `S3M`, `STM`, `MED`, `OKT`, `FAR`, `MTM`, `669`, `ULT`, `AHX`, `HVL`, `MPTM`
- **Multi-Track Container & Archive Unpacking**:
  - Automatically indexes and browses subsongs inside `.zip`, `.7z`, `.rar`, `.lha`, `.lzh`, `.rsn`, `.trd`, `.scl`, `.fdi`, `.dsk`, `.hrip`, `.sid`, `.nsf`, `.nsfe`, `.gbs`, `.sap`, `.kss`, `.hes`, and `.ay` archives.
- **14 Online Chiptune & VGM Catalogues**:
  - **ZXTunes.com**, **ZX-Art.ee**, **The Mod Archive**, **ModLand**, **High Voltage SID Collection (HVSC)**, **Atari SAP Music Archive (ASMA)**, **AYGOR**, **JoshW (31 Console & Computer Archives)**, **Amiga Music Preservation (AMP)**, **Aminet**, **Scene.org**, **VGMRips**, **Khinsider**, and **OverClocked ReMix (OCReMix)**.
- **Online & Local Favourites**:
  - Bookmark any online album, game archive, soundtrack, party, or author collection into your **Favourites** list with one click.
- **Local Chiptunes & Archives Browser**:
  - Select a default local chiptunes directory, play folders and subfolders recursively, and automatically display game metadata (Title, Platform, Year, Publisher/Composer) and Cover Art.
- **Random Chiptune & VGM Radio**:
  - Continuous random radio streams across ModArchive, VGMRips, ZX-Art, ZXTunes, and Khinsider.

## Installation on Daphile / Lyrion Music Server
1. Open **Settings -> Advanced -> Media Server -> Settings -> Plugins** (or **Settings -> Plugins** in Lyrion Music Server).
2. At the bottom of the page under **Additional Repositories**, add:
   ```text
   https://raw.githubusercontent.com/Piernik-cpu/lms-zxtune/main/repo.xml
   ```
3. Click **Apply**, enable **ZXTune Chiptune & VGM Player**, and restart the media server when prompted.
4. *(Note: Once [LMS-Community/lms-plugin-repository#90](https://github.com/LMS-Community/lms-plugin-repository/pull/90) is merged, ZXTune will also appear automatically in the built-in 3rd-party plugin list without needing to add the repository URL manually.)*

## Contributors & AI Transparency Disclosure

I believe in full transparency regarding how this plugin was created:

- **[Vitamin/CAIG (Andrey)](https://zxtune.bitbucket.io/)** — Creator and maintainer of the upstream **[ZXTune](https://github.com/vitamin-caig/zxtune)** project (`r5112`), including the `zxtune123` decoding engine and the original virtual filesystem (`app.zxtune.fs.*`) architecture.
- **[Piernik-cpu](https://github.com/Piernik-cpu)** (myself)— Project initiator, product direction, feature design, live hardware/Daphile server testing, debugging feedback, and repository maintainer.
- **Antigravity (Google DeepMind Advanced Agentic Coding)** — AI coding assistant and co-developer. In pair-programming sessions with **Piernik-cpu**, Antigravity authored the Lyrion Music Server / Daphile Perl plugin architecture (`Plugin.pm`, `ProtocolHandler.pm`, `Catalogs.pm`, `Metadata.pm`, `Settings.pm`), the `zxtune-play` streaming/transcoding pipeline, the HTML settings interface, the automatic game metadata/cover-art resolver, the compliance audit, and the automated packaging/publishing scripts.
- I'll gladly accept any kind of help

## License
Distributed under the **GNU General Public License v3.0 (GPL-3.0)**. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for upstream ZXTune (`Vitamin/CAIG`) credits and source code links.
