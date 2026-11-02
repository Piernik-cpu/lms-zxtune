# ZXTune for Daphile & Lyrion Music Server (LMS)

Complete port of **ZXTune (r5112)** for **Daphile** and **Lyrion Music Server (Logitech Media Server)** on `x86_64-linux`.

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
1. Open **Settings -> Advanced -> Media Server -> Plugins** (or **Settings -> Plugins** in LMS).
2. At the bottom of the page under **Additional Repositories**, add:
   `https://raw.githubusercontent.com/<YOUR_GITHUB_USERNAME>/lms-zxtune/main/repo.xml`
3. Click **Apply**, enable **ZXTune Chiptune & VGM Player**, and restart the media server when prompted.

## License
Distributed under the **GNU General Public License v3.0 (GPL-3.0)**. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for upstream ZXTune (`Vitamin/CAIG`) credits and source code links.
