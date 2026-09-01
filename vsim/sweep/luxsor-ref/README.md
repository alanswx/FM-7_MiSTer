# Luxsor disk 1 — reference renders

Ground truth for `software/D77/LUXSOR_1.D77` (md5 `62c6c90f8843bdad05fec7d906ecdea4`),
rendered by `refs/local/fm77av_headless`. `ref_<N>.png` is named by the **vsim**
frame; the reference was stopped at `round(N * 1.00608)`.

    refs/local/fm77av_headless refs/local/fm77av-roms \
      software/D77/LUXSOR_1.D77 800000000 out.png --stop-at-frame <ref_frame>

`ref_700.png` is the title screen ("LUXSOR — NIGHT OVER EGYPT"), a 320x200
4096-colour analog-palette image. `ours_frame_0700_black.png` is what this core
renders at the same point: all black. Keep both until the 320-mode plane path is
fixed — the pair is what makes "we draw nothing" measurable rather than asserted.
