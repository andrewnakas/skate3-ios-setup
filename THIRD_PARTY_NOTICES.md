# Third-party notices — Skate 3 Recompiled, iOS

The IPA published by this repository is a binary distribution that includes code
written by other people. Their notices are reproduced below, which is what their
licences ask for. `LICENSE` covers only the scripts and packaging in this
repository.

None of this covers **the game**. Skate 3 itself is not distributed here, in the
IPA, or anywhere else in this project — players supply their own copy.

---

## darchap — Skate3-Port

<https://github.com/darchap/Skate3-Port>

The ambient-crowd and movable-prop cuts ship in this build because darchap did
them first. Rather than hiding the meshes at draw time, the three LivingWorld
census managers are hooked and take the game's own "spawned nothing" exit, so an
entity that is never created costs no collision, no voice, no engine noise and no
LivingWorld update slot. That approach is his. Our engine commit that ported it
(`46eb33c`) says so in its body, and the later "Other Skaters" cut is our own
extension of the same technique.

These cuts live in the shared engine rather than in any Android-specific file,
which is why they are in the iOS binary too. The foreground keep-alive service
darchap also wrote is Android-only and is **not** part of this build.

    Copyright (c) 2026 darchap

    BSD 3-Clause License

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

    1. Redistributions of source code must retain the above copyright notice, this
       list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright notice,
       this list of conditions and the following disclaimer in the documentation
       and/or other materials provided with the distribution.

    3. Neither the name of the copyright holder nor the names of its contributors
       may be used to endorse or promote products derived from this software
       without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
    AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
    IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
    ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
    LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
    CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
    SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
    INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
    CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
    ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.

Per clause 3: darchap has not endorsed this build, and nothing here should be
read as him having done so.

---

## The recompilation this is built on

- **Alex McHugh** — [`mchughalex/skate3recomp`](https://github.com/mchughalex/skate3recomp)
  and [`mchughalex/rexglue-skate3`](https://github.com/mchughalex/rexglue-skate3).
  The Skate 3 recompilation itself. This iOS port is downstream of that work and
  would not exist without it.
- **portingpete** — [`portingpete/skate3-recomp`](https://github.com/portingpete/skate3-recomp).
  Early Skate 3 bring-up on ReXGlue.
- **ReXGlue SDK** — [`rexglue/rexglue-sdk`](https://github.com/rexglue/rexglue-sdk).
  The Xbox 360 recompilation runtime and toolkit.
- **Xenia** — Ben Vanik and contributors. The Xbox 360 research ReXGlue derives
  from; the BSD headers on the files that came from it are intact in the source.

Neither upstream Skate 3 repository carries an explicit licence file. Where code
is inherited from them it remains under its authors' terms.

---

## MoltenVK

<https://github.com/KhronosGroup/MoltenVK> — Apache License 2.0, Copyright (c)
2015-2026 The Brenwill Workshop Ltd. Linked statically into the app, because iOS
has no Vulkan loader to load a driver at runtime. The full Apache 2.0 text ships
with MoltenVK's own distribution at the link above.
