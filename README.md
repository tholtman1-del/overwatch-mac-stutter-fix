# Overwatch shader-stutter fix for Mac (CrossOver, Apple Silicon)

Overwatch on a Mac under CrossOver hitches every time something appears for the first time: a new
hero, skin, ability effect or map. Each hitch is the GPU translation layer compiling a shader while
the game waits. This package swaps in a modified build of [DXMT](https://github.com/3Shain/dxmt),
the open-source Direct3D 11 to Metal layer, in which the game never waits for shader compilation.

Measured on an M1 Pro with an **empty shader cache** (the worst case: first time ever, or after
macOS cleared the cache), the same replay, 70 seconds after it loaded:

| | Hitches > 50 ms | Hitches > 100 ms | 1% low FPS |
|---|---|---|---|
| DXMT, stock behaviour (synchronous)* | ~105 per minute | ~75 per minute | 4.9 |
| DXMT + async pipelines only | 26 | 8 | 12.8 |
| **This package** | **1** | **0** | **30.1** |
| For reference: a fully warmed-up cache | 2 per 25 s | 0 | 28 |

\* measured over a shorter 50 s window, scaled to per minute.

With an empty cache it plays as smoothly as a warmed-up one. The trade-off is that a new texture
or effect can appear a moment late (about a second at the start of a match) instead of freezing
the game.

## What it changes, and why it helps

Three changes to DXMT v0.80, each as a separate patch in [`patches/`](patches):

### 1. Async pipelines ([01-dxmt-v0.80-async-pso.patch](patches/01-dxmt-v0.80-async-pso.patch))

Before Metal can draw something it needs a *pipeline*: the shaders compiled for the GPU together
with the draw state. DXMT already compiles these on background threads, but when a draw needs a
pipeline that isn't ready, the thread that records the frame **waits** for it. That wait is the
hitch, from tens of milliseconds up to over a second.

The patch skips draws whose pipeline is still compiling. The object is missing for a frame or two
and then appears; the frame itself is never held up. This works the same way as `dxvk-async` /
`DXVK_ASYNC=1` on Linux. Switch: `DXMT_ASYNC_PSO=1` (on in the launcher).

### 2. Pre-warm ([02-dxmt-v0.80-prewarm.patch](patches/02-dxmt-v0.80-prewarm.patch))

Skipping only works for draws. **Compute** work (post-processing, effects) can't be skipped
safely, so it still waited. A diagnostic build showed seven such waits of up to 69 ms each, right
when a match starts.

A compute pipeline depends on nothing but its shader, so the patch compiles it **as soon as the
game creates the shader**. That's usually behind a loading screen, long before the first use.
Vertex shaders are also translated early, as soon as the game creates their input layout.
Result: zero compute waits. Switch: `DXMT_PREWARM=1`.

### 3. Shader compilers that don't fight the game ([03-dxmt-v0.80-compiler-threads.patch](patches/03-dxmt-v0.80-compiler-threads.patch))

After 1 and 2, most of the remaining hitches were 50–70 ms frames in which nothing in DXMT waited
at all. The cause: DXMT starts up to **twice as many compiler threads as the Mac has cores (20 on
an M1 Pro), all at `THREAD_PRIORITY_TIME_CRITICAL`**. During a burst of new shaders they push
Overwatch's own threads, which already run translated under Rosetta 2, off the CPU.

With async pipelines the game no longer waits for these threads, so they don't need top priority.
The patch adds two switches, and the launcher defaults to **4 threads at below-normal priority**:

- `DXMT_COMPILER_PRIORITY=low|normal` (stock: time critical)
- `DXMT_COMPILER_THREADS=N` (stock: 2 × cores)

| 70 s, empty cache | Hitches > 50 ms | Hitches > 100 ms | 1% low FPS |
|---|---|---|---|
| async + pre-warm, stock compiler threads | 31 | 11 | 12.0 |
| + low priority | 20 | 3 | 17.8 |
| + low priority, 4 threads (default) | **1** | **0** | **30.1** |

(These three runs used a build with extra diagnostic logging, so absolute numbers are slightly
pessimistic.)

### 4. Frame-time log ([04-dxmt-v0.80-frametime-log.patch](patches/04-dxmt-v0.80-frametime-log.patch))

Only used for measuring. With `DXMT_FRAMETIME_LOG=<file>`, every frame time is written to a file;
[`tools/ow-bench.py`](tools/ow-bench.py) turns it into average / median / 1% and 0.1% lows and
hitch counts. Off unless set.

## What it does *not* touch

- **No files in the Overwatch folder** are added or changed, and nothing is injected into the game.
- **CrossOver.app and your bottle stay unmodified.** The installer makes a private copy of
  CrossOver's Wine runtime (an APFS clone, so it's instant and takes no extra space) and only
  changes DXMT inside that copy.
- Starting Battle.net from CrossOver as usual still gives you the stock setup (D3DMetal).

> **Anti-cheat warning.** Overwatch has anti-cheat. This package only changes the graphics layer
> that CrossOver itself already uses (DXMT is a Wine-level Direct3D implementation, like DXVK on
> Linux/Steam Deck). It does not read or change game memory and gives no gameplay advantage. Still,
> it is not stock software. **Use it at your own risk.** I can't guarantee how Blizzard treats it.
>
> One thing I tested and deliberately left out: replacing Wine's `ntdll.dll` makes Overwatch's
> protected loader hang at startup. Don't combine this with other system-DLL mods.

## Requirements

- Apple Silicon Mac (tested: M1 Pro, macOS 27)
- CrossOver 26 (tested: 26.3) with Battle.net and Overwatch installed in a bottle
- Overwatch set to **DirectX 11** (Options → Video). DXMT has no DirectX 12.

## Install

```sh
git clone https://github.com/tholtman1-del/overwatch-mac-stutter-fix.git
cd overwatch-mac-stutter-fix
./install.command
```

The installer finds the bottle with Battle.net (or use `--bottle "Name"`), clones CrossOver's
runtime, downloads [DXMT v0.80](https://github.com/3Shain/dxmt/releases/tag/v0.80) (checksum
verified) and adds the patched `d3d11.dll` from [`payload/`](payload).

## Play

Double-click **Overwatch (stutter fix)** on your Desktop and click **Play** in Battle.net. If
Battle.net is already running, the launcher offers to restart it, because Overwatch inherits its
graphics setup from Battle.net.

Options (`~/Library/Application Support/OverwatchMac/launch.command --help`):

| Option | Effect |
|---|---|
| `--fps` | Apple's Metal performance HUD |
| `--sync` | async pipelines off (for comparison) |
| `--d3dmetal` | CrossOver's stock D3DMetal (for comparison) |
| `--bench NAME` | log frame times to `~/Library/Application Support/OverwatchMac/bench/` |
| `--cold` | start with an empty shader cache (your cache is saved) |
| `--restore-cache` | put the saved shader cache back |

Example of tuning: `DXMT_COMPILER_THREADS=6 ~/Library/Application\ Support/OverwatchMac/launch.command`.
On a Mac with more cores, a few more threads may shorten pop-in without bringing hitches back.

## Measure it yourself

Overwatch has no built-in benchmark, but replays (Career Profile → History → Replays) play back
identically every time:

```sh
L=~/Library/Application\ Support/OverwatchMac/launch.command
$L --bench replay --cold --sync      # play the replay ~2 min, quit
$L --bench replay --cold             # same replay, same length
$L --restore-cache
python3 ~/Library/Application\ Support/OverwatchMac/tools/ow-bench.py --timeline \
  ~/Library/Application\ Support/OverwatchMac/bench/*.txt
```

Use `--skip`/`--len` to compare the same stretch of the replay (the replay-load hitch is a good
anchor). Note: each configuration above was measured once, and cold runs vary a few hitches from
run to run. The macOS system Metal cache can't be cleared per game, so later cold runs get a
small head start.

## Known limitations

- DirectX 11 only. DirectX 12 runs on CrossOver's D3DMetal (use `--d3dmetal`).
- DXMT logs `CreateGeometryShaderWithStreamOutput: not supported` for one Overwatch shader. I
  haven't noticed a visible problem.
- The game's video codec `bink2w64.dll` lacks the NX flag, so Wine makes the process memory
  executable. This can't be fixed without touching game or Wine system files (see the warning
  above). Overwatch runs fine regardless.
- After a CrossOver update, run `install.command` again (the launcher reminds you).
- The FPS cap of about 60 in the tables is the game's 60 Hz display mode, not the fix.

## Uninstall

```sh
~/Library/Application\ Support/OverwatchMac/uninstall.command
```

## Building the DLL yourself

`payload/d3d11.dll` is DXMT v0.80 with the four patches applied in order. The patches apply
cleanly to the `v0.80` tag and reproduce the shipped source exactly. Build the 64-bit PE
`d3d11.dll` with mingw-w64 and Meson as described in DXMT's README:

```sh
git clone https://github.com/3Shain/dxmt.git && cd dxmt && git checkout v0.80
for p in /path/to/patches/*.patch; do git apply "$p"; done
meson setup build64 --cross-file build-win64.txt --buildtype release \
  -Dwine_build_path=/path/to/wine-build64 -Dwine_builtin_dll=true \
  -Dcpp_args="['-include','iomanip','-include','cstdint']"
ninja -C build64 src/d3d11/d3d11.dll
```

(Only `d3d11.dll` is needed; `winemetal.so` comes from the official v0.80 release. The
`-include` flags are for newer mingw-w64 GCC.) Then strip it and mark it as a Wine builtin with
`winebuild --builtin d3d11.dll`.

## Credits and license

- [DXMT](https://github.com/3Shain/dxmt) by Feifan He (3Shain) and contributors, MIT license
  ([licenses/DXMT-LICENSE](licenses/DXMT-LICENSE)). The modified `d3d11.dll` and the patches are
  under the same license.
- Scripts and tools in this repository: MIT ([LICENSE](LICENSE)).
- Not affiliated with or endorsed by Blizzard Entertainment, CodeWeavers or Apple. Overwatch is a
  trademark of Blizzard Entertainment.
