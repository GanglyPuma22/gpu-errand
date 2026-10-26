---
layout: page
title: Sound effects with Stable Audio Open on Colab
permalink: /recipes/sound-effects-stable-audio-open-colab/
description: Generate game sound effects from text with Stable Audio Open 1.0 on a Google Colab L4, from one job file, without putting your Hugging Face token on the runtime.
---

The `stable-audio-open-sfx` recipe makes sound effects from text with [Stable Audio Open 1.0](https://huggingface.co/stabilityai/stable-audio-open-1.0), through Diffusers. Each seed gives one effect, up to 47 seconds long, at 44.1 kHz stereo.

**Measured:** three 5 s effects took 9 minutes on a Colab L4 and used 0.21 compute units, including setup and the 5 GB model download. Each effect took about 14 s to generate.

## The job

```json
{
  "schema": 1, "id": "sword-swings-1", "type": "model-run",
  "recipe": "stable-audio-open-sfx", "gpu": "L4",
  "plan": {
    "steps": 100, "guidance": 7.0, "seconds": 5,
    "negative_prompt": "music, speech, voice, low quality, distortion",
    "cues": [
      {"id": "heavy-sword-swing", "seeds": [2311, 2312],
       "prompt": "A single heavy two-handed steel sword swung hard through the air: deep, slow, weighty whoosh with a low rumble, close up, dry, no impact"},
      {"id": "metal-impact", "seeds": [2313],
       "prompt": "Steel blade striking a steel cable: sharp metallic clang with short ringing tail, close up, dry"}
    ]
  },
  "max_minutes": 15, "max_units": 0.5, "max_rate": 3, "results_max_mb": 60
}
```

## Your Hugging Face login stays on your machine

Stable Audio Open is gated: accept its license on the model page with your Hugging Face account first. The runner reads your login on the host from `HF_TOKEN`, `HF_TOKEN_PATH` (a bare token or an env file with `HF_TOKEN=`) or `~/.cache/huggingface/token`. It turns that into short-lived download links for the exact files at the pinned revision. The runtime downloads them and checks each SHA-256, and the token never leaves your machine.

## What comes back

In the results folder's `out/`:

- `originals/<cue>-<seed>.wav`: the effect as generated, 32-bit float. Peaks can go above 1.0; that's headroom, not clipping.
- `previews/<cue>-<seed>.wav`: 16-bit, peaking at -1 dBFS, ready to audition.
- `receipt.json`: each file's hash, length, peak and loudness, plus timings.

## Tips from our runs

- Words like "heavy" don't guarantee weight. In our first batch a "heavy swing" came out light. Describe the sound itself ("deep, slow whoosh with a low rumble") and ask for two or three seeds.
- Add "dry, close up" for game effects you'll mix yourself, and "no impact" when you want the swing alone.
- Listen to every preview before you import anything. The receipt proves the files are valid, not that they fit.

## License

Stable Audio Open 1.0 is under the Stability AI Community License. Read its terms for commercial use before you ship effects in a product.
