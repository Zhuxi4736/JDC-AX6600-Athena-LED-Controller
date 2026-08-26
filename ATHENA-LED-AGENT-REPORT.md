# Athena LED Control-Port Animation Feasibility — Technical Report

**Repo:** `unraveloop/JDC-AX6600-Athena-LED-Controller` (clone: `C:\Users\47362\JDC-AX6600-Athena-LED-Controller\`)
**Target:** JDCloud AX6600 "Athena" — TM1628A 27×5 dot-matrix LED (14+13 columns)
**Daemon:** Rust (`athena-led`), listens on 127.0.0.1 when started with `--control-port <N>`

---

## (1) Control-Port Protocol — Exact Command Set

Source: `athena-led/src/control.rs` lines 49–128 (`handle_command`).
Wire format: TCP `127.0.0.1:<port>`, **one command per line**, `\n` terminator, server replies with `OK\n` / `ERR …\n` / `PONG\n`. 5-second idle timeout per connection (line 166).

| Command | Syntax | Effect |
|---|---|---|
| `ping` | `ping` | Liveness probe → `PONG` |
| `next` | `next` | Advance to next module (= short-press button) |
| `home` | `home` | Jump to module 1, set `go_home` flag |
| `off` / `sleep` | `off` | Force display off (`tx.send(-1)`) |
| `wake` | `wake` | Wake from sleep (`tx.send(1)`) |
| `toggle` | `toggle` | Invert on/off state |
| `light` | `light <0–7>` or `light auto` | Temporary brightness override (overrides night-mode brightness until `auto`) |
| `show` | `show <1–300> <text…>` | One-shot "interruption" — display `text` for N seconds, then resume normal rotation. **`<N>` is the lockout duration; not a scroll length.** |

Validation: `show` requires secs in `[1, 300]` and a non-empty text body, else `ERR 用法: show <1-300秒> <文本>`.

**Scrolling?** Partial — but **only via the regular module pipeline, not via `show`.** In `athena-led/src/led_screen.rs`:
- `write_data` (line 268) — used by `pending_show` — goes through `flow()` (line 403) **iff rendered text > 27 columns**. `flow()` shifts one column every 128 ms (≈7.8 fps, single-pass left→right, no wrap).
- For text ≤ 27 columns it's `static_display()` (line 420): center-pad, no scroll.

So `show <secs> <text>` with a short string renders **statically**. There is **no marquee mode flag** on the `show` command itself.

---

## (2) Animation / Multi-Frame Support

**There is a built-in frame sequencer — but it is NOT exposed via the control port.**

`athena-led/src/led_screen.rs` lines 328–377: `play_animation(file_name, duration_secs, status)` reads a pre-baked `.bin` raw frame stream from `/etc/athena-led/anim/<file>`, slices it into 27-byte frames (one full screen per frame), and pushes each frame at **66 ms intervals ≈ 15 fps** (line 359). It is wired into the scheduler exclusively via the `anim` module keyword in `--display-order` (`scheduler.rs` line 570), where the file is a static `module.param`. A 5MB cap ⇒ ≈3 hours of 15fps content. Authoring tool: `tools/convert_vid.py` (ffmpeg → column-mapped `.bin`); preview with `tools/preview_bin.py`.

**Control port has no `anim`/`frame` command.** The full command list is exactly the 8 above; `handle_command` returns `ERR 未知指令` for anything else (line 126).

**Therefore, animation through the control port means the client scripting `show` in a loop.** Each `show` queues text that is then re-rendered in a 100 ms loop (scheduler.rs line 269) — a new `show` command *does* preempt the prior one (it nudges the watch channel at control.rs line 118), so a fast client can drive frame changes at the loop's 100 ms cadence ≈ **10 fps ceiling** for static frames. A scrolling text would drop to ≈7.8 fps because each `flow()` pass is locked to the 128 ms column shift.

---

## (3) Render Method & Practical Update Rate

- **Bitmap font only.** All glyphs come from `athena-led/src/char_dict.rs` (~65 entries: 0-9, A-Z, a handful of punctuation, plus 12 weather icons `☀☼☂☔☁🌥⚡☇❄❅🌫℃`). Lookup at led_screen.rs line 304 uses `ch.to_ascii_uppercase()` then `CHAR_DICT.get(&key)`.
- **Unicode emoticons like `(◕‿◕)` will NOT render** — non-ASCII chars fall through the `if let Some(bytes) = …` and produce blank columns. ASCII faces like `:)` or `<3` (if hand-drawn into the dict) would work; stock faces are not present.
- **No raw-pixel upload** to the control port. The 27-byte raw frame path exists only inside `play_animation` from a local `.bin` file.

**Practical frame rate for a `show`-driven animated "pet":**
- Single `show` request: TCP RTT + cmd parse + scheduler poll interval → ~tens of ms on a 127.0.0.1 loopback.
- Render loop: 100 ms per re-write (scheduler.rs line 269) — the scheduler rewrites the same text every 100 ms while `pending_show` is active.
- **Effective ceiling: ~10 fps for static frames, 2–8 fps for short text sequences** — feasible, but every frame is one full `show` syscall, so a 6-frame "blink" loop costs 6 line-protocol commands per cycle.

---

## Verdict — 2–8 fps Lo-Fi Animated Pet via Control Port

**Conditionally feasible, with caveats:**

1. **Render path is viable.** A client pushing 2–8 `show` commands/sec will produce visible frame changes; 10 fps is the architectural ceiling. The "blinking pet" use case is realistic.
2. **No native multi-frame / GIF mode** on the control port. You must script frame sequencing client-side.
3. **ASCII-art only.** Faces must be drawn in the existing 5-pixel-tall, 3-pixel-wide per-glyph bitmap dictionary or use existing letters. Kaomoji like `(◕‿◕)` are dropped silently. Practical alternative: spell `:-)` / `^_~` / `<3` etc., or hand-add new glyphs to `char_dict.rs` and rebuild.
4. **Scrolling intro** is free if your pet's intro line is >27 columns; it will auto-flow at 7.8 fps.
5. **State-LEDs (the 4 corner indicators) cannot be controlled from the port** — they're set indirectly via brightness alerts, not the protocol.

**Recommendation:** The control-port path supports a 2–8 fps blink/bounce/mouth-flap pet using ASCII-art frames, as long as the client owns the frame loop. For richer, smoother animation (true 15 fps pixel-precise) use the `anim` module with a pre-converted `.bin` (out-of-band file drop, no socket), or fork the daemon to add a `frame <27-bytes-hex>` command — neither requires kernel/board changes.
