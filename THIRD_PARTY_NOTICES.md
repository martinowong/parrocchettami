# Third-party notices

Parrocchettami source code is licensed separately under the GNU General
Public License, version 3 or later. See `LICENSE`.

Parrocchettami distributes or downloads the following third-party components.

## parakeet.cpp

Source: https://github.com/mudler/parakeet.cpp

Created by Ettore Di Giacinto (mudler), with contributions from the
parakeet.cpp community.

MIT License

Copyright (c) 2026 the parakeet.cpp authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## NVIDIA Parakeet TDT 0.6B v3 / GGUF conversion

Original model: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3

GGUF distribution: https://huggingface.co/mudler/parakeet-cpp-gguf

The model weights are derived from NVIDIA's Parakeet TDT 0.6B v3 and are
licensed under Creative Commons Attribution 4.0 International (CC BY 4.0):

https://creativecommons.org/licenses/by/4.0/

The distributed file is a Q5_K quantized GGUF conversion named
`tdt-0.6b-v3-q5_k.gguf`. Parrocchettami does not claim endorsement by NVIDIA,
the parakeet.cpp authors, or the GGUF distributor.

## Opus tools and libraries

Source: https://opus-codec.org/

Parrocchettami can bundle `opusdec` from Opus Tools to decode OPUS and
WhatsApp voice-note audio before local transcription.

Relevant bundled components may include:

- opus-tools / opusdec - BSD-2-Clause
- libopus - BSD-3-Clause
- opusfile - BSD-3-Clause
- libogg - BSD-3-Clause

Copyright belongs to the Xiph.Org Foundation and the respective Opus/Xiph
contributors. License texts and source distributions are available from the
Opus and Xiph project sites.

## OpenSSL

Source: https://www.openssl.org/

The bundled `opusdec` dependency chain may include OpenSSL 3 libraries when
built from the Homebrew `opus-tools` package.

OpenSSL 3 is licensed under the Apache License 2.0. Copyright belongs to the
OpenSSL Project Authors. License text and source distributions are available
from the OpenSSL project site.
