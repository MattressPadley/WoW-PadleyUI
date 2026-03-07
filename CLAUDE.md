# PadleyUI

WoW addon that skins built-in Blizzard UI frames with a flat/minimal aesthetic.

## WoW Addon API — Taint Rules

The DamageMeter (and other secure Blizzard frames) use `securecallfunction` / `secureexecuterange` to protect combat data. Patch 12.0 introduced **Secret Values** — combat API results become un-readable "secret" values when accessed from tainted (insecure) execution paths. Follow these rules to avoid taint errors:

### DO (Safe)

- **Hook instances, not mixin tables.** `hooksecurefunc(frame, "Method", hook)` creates a C-level wrapper directly on the frame. `securecallfunction` recognises it and runs the original securely, then the hook insecurely, with proper taint isolation.
- **Use separate child frames for backdrops.** `CreateFrame("Frame", nil, parent, "BackdropTemplate")` creates an addon-owned frame. Safe to call `SetBackdrop`, `SetBackdropColor`, etc. on it.
- **Track skinned frames in external Lua tables** (e.g. `local skinnedWindows = {}`), not by writing keys onto Blizzard frames.
- **Modify visual properties on Blizzard frames** — `SetStatusBarTexture`, `SetAtlas`, `SetTexture`, `Hide`, `SetAlpha`, `ClearAllPoints`, `SetPoint` are all safe. They taint only the specific property they touch.
- **Hook ScrollBox.Update on the instance** to skin entries after all secure Init calls finish. Iterate with `ForEachFrame`.

### DON'T (Causes Taint)

- **Never `hooksecurefunc(MixinTable, "Method", hook)`.** `Mixin()` copies the hooked function as a plain Lua value. The copy loses its C-level hooksecurefunc metadata, so `securecallfunction` runs the entire function insecurely — making combat values "secret."
- **Never `Mixin(blizzardFrame, BackdropTemplateMixin)`.** This writes tainted keys onto the Blizzard frame's table. Secure code encountering these keys gets tainted. Use `CreateFrame("Frame", nil, button, "BackdropTemplate")` instead.
- **Never `SetHeight`/`SetWidth`/`SetSize` on Blizzard dropdown buttons inside hooks.** Triggers layout cascades that cause `Refresh` to re-enter in the addon's tainted context.
- **Never modify `window.NotActive` or `window.SessionTimer`** — not `SetFont`, not `ClearAllPoints`/`SetPoint`. Their layout state is evaluated during secure `Refresh`; tainting any property poisons the entire execution context.
- **Never `SetFont` on other FontStrings read during secure execution** (e.g. `statusBar.Name`, `statusBar.Value`). The tainted FontString causes secret-value errors when `GetText()` is called in secure code.
- **Never write custom keys to frames in secure execution paths** (e.g. `blizzardFrame._myFlag = true`). Use external tracking tables instead.
