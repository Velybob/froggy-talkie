# Third-party notices — Froggy Talkie 0.5.0

Froggy Talkie's own source and artwork are under the MIT License in `LICENSE`.
That license does not relicense third-party code, resources or model weights.
The icon is the project-approved generated artwork; the original PNG is kept
unchanged and only masked/scaled by the icon build scripts.

## Code shipped or linked by the application

| Component | Pinned version / revision | License and notices |
|---|---|---|
| FluidInference/FluidAudio | 0.18.2 / `e396cf780c4abf8e395087467c0585d3b0d17f68` | Apache-2.0, `Licenses/FluidAudio/LICENSE` |
| FluidInference/text-processing-rs (NemoTextProcessing binary target) | v0.3.1; artifact SHA-256 `5fa8c10d4ec26c1bb2413125f351a7222a4c68a23b74476680fbada7e26fc6aa` | Apache-2.0 and dependency terms, `Licenses/NemoTextProcessing/` |
| fastcluster, VBx and other FluidAudio incorporated components | As included in the pinned FluidAudio revision | Original notices retained in `Licenses/FluidAudio/ThirdPartyLicenses/` |

Sources: https://github.com/FluidInference/FluidAudio and
https://github.com/FluidInference/text-processing-rs/tree/v0.3.1.

Swift 6.1 builds FluidAudio's larger default target, including TTS/diarization
code and the NeMo binary dependency even though the GUI calls only Parakeet ASR.
The shipped license set conservatively retains FluidAudio's supplied notices.
`Licenses/NemoTextProcessing/RustCrates` retains license files from the exact
registry archives in the v0.3.1 Cargo.lock (including build/test/other-platform
entries); archive SHA-256 and source URLs are recorded in
`rust-license-inventory.json`. Inclusion of a notice does not imply that the
corresponding optional model or data is included in the app.

**Excluded resources:** `luxtts_en_us_lexicon.tsv.zz` and
`luxtts_en_us_g2p_aux.json` are not shipped. They carry additional GPL-3.0-or-later
and CC-BY-SA-4.0 conditions described by FluidAudio. Its notice explicitly
permits apps not using LuxTTS to omit these files. No Kokoro/LuxTTS/diarization
model weights, language dictionaries or research datasets are distributed.

## Benchmark-only dependencies

| Component | Version / revision | License |
|---|---|---|
| Argmax OSS / WhisperKit | 1.1.1 / `1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4` | MIT; incorporated swift-transformers portions Apache-2.0, see `Licenses/Argmax/LICENSE` and `NOTICES` |
| Apple swift-argument-parser | 1.8.2 / `6a52f3251125d74daf04fcbd5e6f08a75d074382` | Apache-2.0, `Licenses/SwiftArgumentParser/LICENSE.txt` |

Sources: https://github.com/argmaxinc/argmax-oss-swift and
https://github.com/apple/swift-argument-parser. These are resolved for the
optional benchmark; WhisperKit is not a dependency of the GUI target.

## Separately downloaded Parakeet Ultra model

License: **Creative Commons Attribution 4.0 International (CC BY 4.0)**.
Full license: `Licenses/Parakeet/CC-BY-4.0.txt` and
https://creativecommons.org/licenses/by/4.0/.

Attribution / provenance:
- NVIDIA — original `parakeet-tdt-0.6b-v3` model:
  https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
- Moondream — Parakeet Ultra post-training:
  https://huggingface.co/moondream/parakeet-ultra
- FluidInference — Core ML conversion and quantization:
  https://huggingface.co/FluidInference/parakeet-ultra-coreml
  revision `95eaa59a39d4394f047a4dc5cce480388a60d1b6`.

Froggy Talkie downloads those pinned Core ML files unchanged. Conversion and
quantization were performed upstream by FluidInference; the exact model card
is retained in `Licenses/Parakeet/FluidInference-model-card.md`. This project
is not endorsed by NVIDIA, Moondream or FluidInference. Model weights are not
included in the source archive or application ZIP. Attribution is retained
in the app even when the files are downloaded directly from the provider.
