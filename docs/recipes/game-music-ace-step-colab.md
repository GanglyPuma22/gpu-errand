---
layout: recipe
title: Game music with ACE-Step on Colab
permalink: /recipes/game-music-ace-step-colab/
description: Generate instrumental game music and music loops with ACE-Step 1.5 on a Google Colab A100, from one job file, with a compute-unit cap and a receipt.
---

The `ace-step-music` recipe makes instrumental tracks from a text description with [ACE-Step 1.5](https://github.com/ace-step/ACE-Step-1.5). You can ask for a crossfaded loop as well, so the end runs back into the start for in-game music. Each seed gives one track.

In our runs, one 60 s cue plus a 52 s loop took 5 minutes on a Colab A100 and used 0.44 compute units, including setup. A batch of five 3-minute tracks took about 97 s per track after 6 minutes of setup (1.49 units). Peak GPU memory was about 22 GB, so it needs an A100; an L4 is not offered.

## The job

```json
{
  "schema": 1, "id": "chase-music-1", "type": "model-run",
  "recipe": "ace-step-music", "gpu": "A100",
  "plan": {
    "seconds": 60, "inference_steps": 50, "guidance_scale": 7.0,
    "loop_crossfade_seconds": 8,
    "cues": [{
      "id": "rooftop-chase", "bpm": 120, "keyscale": "D minor", "seeds": [3101],
      "caption": "Tense rooftop chase underscore for an action game. Driving taiko and frame drums, low staccato strings, metallic swells, short brass stabs. Instrumental, no voices. Steady energy, repeating phrases, no big intro or final cadence; loopable game music."
    }]
  },
  "max_minutes": 25, "max_units": 2, "max_rate": 7, "results_max_mb": 200
}
```

```bash
gpu-errand plan chase-music-1.json
COLAB_SESSION=music-1 gpu-errand run chase-music-1.json
```

## What comes back

In the results folder's `out/`:

- `originals/<cue>-<seed>/*.flac`: the track as generated, 48 kHz stereo.
- `loops/<cue>-<seed>.wav`: the loop, with the last few seconds crossfaded into the start (when `loop_crossfade_seconds` is set).
- `seams/<cue>-<seed>-wrap.wav`: 24 s that plays across the loop point, so you can hear whether the seam works.
- `receipt.json`: model revisions, timings, peak memory and each file's hash, length, peak and loudness.

## Tips from our runs

- Say how the music will be used as well as its genre. "No big intro or final cadence; loopable" got us music that loops well.
- Pin `bpm` and `keyscale` so cues for the same game fit together.
- Listen to the seam file before you use a loop. The receipt checks that the files are valid. It can't tell you whether the loop sounds right.
- Several seeds per cue give you takes to choose from; the model loads once per job, so extra seeds are cheap.

## License

Check the [ACE-Step repository](https://github.com/ace-step/ACE-Step-1.5) and each model card for commercial-use terms before you ship tracks in a game.
