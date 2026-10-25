---
layout: page
title: Headless Godot capture on a cloud GPU
permalink: /recipes/headless-godot-capture-gpu/
description: Record Godot gameplay clips and stills on a Google Colab GPU with no screen attached, using a godot-capture job, a virtual display and Vulkan on the NVIDIA driver.
---

A `godot-capture` job runs your game's own capture command on a Colab GPU. The runner gives it a virtual screen (Xvfb) with Vulkan on the runtime's NVIDIA GPU, so Godot's Forward+ renderer draws as it would on a desktop. Use it for review clips, still frames from fixed cameras, or comparing two builds.

**Measured:** two gameplay clips of a small Godot 4.4 game took 3.3 minutes on a Colab L4, about 0.02 compute units. The `gpu=nvidia` line in the results confirmed the GPU drew the frames.

## The job

```json
{
  "schema": 1, "id": "godot-clips-1", "type": "godot-capture",
  "repo": "your-name/your-game", "ref": "main",
  "godot": {
    "url": "https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_linux.x86_64.zip",
    "sha256": "d6e382fb531019f85630c1f485a561a0d20c4a2344b6c3847735cfee7da812aa"
  },
  "setup": "\"$GODOT\" --headless --import",
  "command": "\"$GODOT\" --path . --write-movie \"$OUT_DIR/clip.avi\" --fixed-fps 30 --quit-after 300 res://tools/capture_scene.tscn",
  "gpu": "L4", "max_minutes": 30, "results_max_mb": 200
}
```

The runner packs exactly the commit `ref` names, so push first. `$GODOT` points at the engine it downloaded and checked. Anything you write under `$OUT_DIR` comes back.

## Things to know

- **Use the movie writer.** `--write-movie` with `--fixed-fps` advances game time one step per frame. Clips play at normal speed and the sound stays in sync, however slow the drawing is.
- **Don't benchmark on it.** Presenting to the virtual screen fails on Colab (VkResult -13), which stalls each frame. Frames still render correctly, but frame times and GPU timers can't be trusted.
- **Wall-clock effects drift.** Anything driven by real time rather than game time (some glows, timers) runs at the wrong speed in a fixed-step recording.
- **No GPU at all?** `gpu-errand here job.json <checkout> <out>` runs the same job on your machine with a software Vulkan driver (`apt install xvfb ffmpeg mesa-vulkan-drivers`). It's free and correct, just slow: about 2 frames a second at 1280x720 on 4 cores.
- **Skip drawing while you wait.** If your capture script fast-forwards to a moment, turn off rendering until shortly before it. In Godot 4.4, `RenderingServer.render_loop_enabled = false` together with `get_tree().root.disable_3d = true` took a software-rendered frame from about 270 ms to 25 ms.
