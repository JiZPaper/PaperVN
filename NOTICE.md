# Notice

Copyright © 2026 Paper. All rights reserved except as stated below.

## License

Unless otherwise noted, the source code and other original material in this repository are licensed under the [Creative Commons Attribution-ShareAlike 4.0 International License](https://creativecommons.org/licenses/by-sa/4.0/) (CC BY-SA 4.0). The full license text is in [LICENSE](LICENSE).

When you share this material or adaptations of it, you must give appropriate credit to JiZPaper (简纸Paper), link to the license, indicate whether changes were made, and distribute your contributions under the same license.

## Not covered by the license

The following are **not** licensed under CC BY-SA 4.0 or any other license. No rights to them are granted:

- **The PaperVN name.** “PaperVN” identifies the official app and its services. Adaptations you distribute must use a different name and must not suggest that they are the official app or are endorsed by JiZPaper. You may use the name only to state, accurately, that your work is based on PaperVN.
- **The PaperVN icon and logo**, including all files in:
  - `PaperVN/PaperVN.icon/`
  - `PaperVN/Assets.xcassets/PaperVNAppIcon.imageset/`
  - `docs/images/app-icon.png`

  Adaptations you distribute must replace them with your own artwork.
- **The donation QR codes** in `docs/images/donate/`. Adaptations you distribute must remove them or replace them with your own.

## Third-party material

The following material belongs to its respective owners and is not covered by the license above:

- `Dependencies/ZIPFoundation/` — ZIPFoundation by Thomas Zoechling, licensed under the MIT License. See [`Dependencies/ZIPFoundation/LICENSE`](Dependencies/ZIPFoundation/LICENSE).
- `Dependencies/Siglus/SiglusCore.xcframework` — built by `Tools/构建Siglus.sh` from unmodified [siglus_rs](https://github.com/xmoezzz/siglus_rs) by xmoezzz (the commit is in `Dependencies/Siglus/SIGLUS_RS_COMMIT`), licensed under the Mozilla Public License 2.0. See [`Dependencies/Siglus/LICENSE-MPL-2.0`](Dependencies/Siglus/LICENSE-MPL-2.0). The interface crate in `Dependencies/Siglus/PaperVNSiglus/` is also licensed under MPL 2.0. siglus_rs depends on further open source crates; they are listed with their licenses at [papervn.jizpaper.com/license](https://papervn.jizpaper.com/license).
- `Dependencies/KiriKiri/KiriKiriCore.xcframework` and `Dependencies/KiriKiri/Sources/KiriKiri/Resources/res/` — built by `Tools/构建KiriKiri.sh` from [krkr2](https://github.com/2468785842/krkr2) (the commit is in `Dependencies/KiriKiri/KRKR2_COMMIT`), licensed under the MIT License. See [`Dependencies/KiriKiri/LICENSE-krkr2`](Dependencies/KiriKiri/LICENSE-krkr2). PaperVN's changes to krkr2 are in `Dependencies/KiriKiri/patches/krkr2-ios.patch`, and the vcpkg port changes are in `Dependencies/KiriKiri/vcpkg/ports/`. The patch also adds the KiriKiri plug-ins [KAGParserEx](https://github.com/wtnbgo/KAGParserEx), [layerExBTOA](https://github.com/wtnbgo/layerExBTOA), [layerExImage](https://github.com/wtnbgo/layerExImage), [layerExRaster](https://github.com/wtnbgo/layerExRaster), [extrans](https://github.com/wamsoft/extrans), [extNagano](https://github.com/wamsoft/extNagano), and [AlphaMovie](https://github.com/wamsoft/AlphaMovie), licensed under the KiriKiri license (parts of layerExImage are based on CxImage, under a zlib-style license). The library statically links components under their own licenses, including FFmpeg, 7-Zip, OpenAL Soft, and libiconv under the LGPL; they are listed at [papervn.jizpaper.com/license](https://papervn.jizpaper.com/license).
- `Dependencies/KiriKiri/Sources/KiriKiri/Resources/renpyweb/` — the WebAssembly runtime of [Ren'Py](https://www.renpy.org) 8.5.3 by Tom Rothamel and contributors, licensed under the MIT License, with components under other licenses including the LGPL (SDL2, FFmpeg). See `LICENSE-renpy.txt` in that folder. `game.zip` contains the unmodified `renpy` folder from the Ren'Py SDK, with `.py` replaced by compiled `.pyc` as Ren'Py's own web export does.
- The GPU drawing classes in `Dependencies/KiriKiri/KiriKiriCore.xcframework` (`OGLDrawDevice`, `Canvas`, `Texture`, `ShaderProgram`, and related classes) and the `krkrgles` plugin are from [KIRIKIRI-Z](https://github.com/wamsoft/krkrz) and [krkrgles](https://github.com/wamsoft/krkrgles), © W.Dee and contributors, under the license in [`Dependencies/KiriKiri/LICENSE-krkrz`](Dependencies/KiriKiri/LICENSE-krkrz). PaperVN's changes are in `Dependencies/KiriKiri/patches/krkrz-gl-ios.patch` and `krkrgles-ios.patch`.
- KTX texture support in the same library uses the read-only parts of [KTX-Software](https://github.com/KhronosGroup/KTX-Software) by The Khronos Group and contributors and [Basis Universal](https://github.com/BinomialLLC/basis_universal) by Binomial LLC, both under the Apache License 2.0, and Zstandard under the BSD License. See [`Dependencies/KiriKiri/LICENSE-ktx.md`](Dependencies/KiriKiri/LICENSE-ktx.md).
- `PaperVN/非用户界面/视觉小说运行/NScripterNT表.swift` is converted from [NtDec](https://github.com/UlyssesWu/NtDec) by Ulysses, licensed under the MIT License. See [`Dependencies/KiriKiri/LICENSE-ntdec`](Dependencies/KiriKiri/LICENSE-ntdec).
- `Dependencies/KiriKiri/Sources/KiriKiri/Resources/soundfont/GeneralUser-GS.sf2` is [GeneralUser GS](https://github.com/mrbumpy409/GeneralUser-GS) by S. Christian Collins. See `LICENSE-GeneralUser-GS.txt` in that folder.
- `Dependencies/KiriKiri/Sources/KiriKiri/Resources/ruffle/` — the WebAssembly build of [Ruffle](https://ruffle.rs) 0.7.1, licensed under MIT or Apache-2.0 (`LICENSE_MIT` and `LICENSE_APACHE` in the same folder). PaperVN uses it to play Flash files for the YU-RIS `FLASH` command.
- `Dependencies/KiriKiri/Sources/PaperVNMPEG/pl_mpeg.h` — [PL_MPEG](https://github.com/phoboslab/pl_mpeg) by Dominic Szablewski, licensed under the MIT License.
- The Live2D support in `Dependencies/KiriKiri/KiriKiriCore.xcframework` includes [krkrlive2d](https://github.com/wamsoft/krkrlive2d) (PaperVN's changes are in `Dependencies/KiriKiri/patches/krkrlive2d-ios.patch`), [wtnbgo/live2d](https://github.com/wtnbgo/live2d), and Live2D Cubism Framework under the Live2D Open Software License, Live2D Cubism Core under the Live2D Proprietary Software License, and [minizip-ng](https://github.com/zlib-ng/minizip-ng) under the zlib License. See [`Dependencies/KiriKiri/LICENSE-live2d-driver.md`](Dependencies/KiriKiri/LICENSE-live2d-driver.md) and [`Dependencies/KiriKiri/LICENSE-live2d-core.md`](Dependencies/KiriKiri/LICENSE-live2d-core.md).
- `PaperVN/Assets.xcassets/BilibiliIcon.imageset/`, `DiscordIcon.imageset/`, `QQIcon.imageset/`, `TelegramIcon.imageset/` — trademarks of their respective owners, used only to link to the corresponding services.
- `PaperVN/Assets.xcassets/LiquidGlassPreviewHoshizora.imageset/` — third-party artwork, used only as a settings preview. All rights belong to its owner.
- Visual-novel covers, screenshots, and character artwork shown in `docs/images/screenshots/` belong to their respective rights holders and appear only to illustrate the app.
- Visual-novel metadata and images that the app retrieves or bundles, including data derived from [VNDB](https://vndb.org/), remain subject to the terms of their sources, such as the [VNDB Data License](https://vndb.org/d17).
- The Hiro智能 search model downloaded by the app includes Chinese titles, aliases, and tags derived from the [Bangumi](https://bgm.tv/) wiki data archive ([bangumi/Archive](https://github.com/bangumi/Archive)), which remain subject to Bangumi's terms.
- Event data in `PaperVN/Resources/` remains subject to the terms of its original sources.

## Online services

The PaperVN server and its hosted services (Today, PaperVN Event, PaperVN Connect, feedback, system status, and translation submissions) are not part of this repository. They are operated for the official app and are subject to the [Terms of Service](https://papervn.jizpaper.com/TermsOfService.html) and [Privacy Policy](https://papervn.jizpaper.com/PrivacyPolicy.html). Access from other builds may be limited or revoked at any time.

## Private configuration

The official build includes a small private configuration that is not published, including certain parental-control parameters and service credentials. Builds from this repository use the public defaults in `PaperVN/非用户界面/内容安全默认配置.swift`.
