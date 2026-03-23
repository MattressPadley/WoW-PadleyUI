# PadleyUI

WoW addon that skins built-in Blizzard UI frames with a flat/minimal aesthetic.

## WoW 12.0 (Midnight) Addon API — Taint & Secret Values Reference

### Overview

Patch 12.0 introduced **Secret Values** — a mechanism that wraps sensitive Lua values in opaque containers. Untainted (secure/Blizzard) code can read them normally; tainted (addon) code can receive and pass them to approved APIs but **cannot inspect, compare, or do math on them**. The goal: cosmetic/UI addons remain fully supported; combat-automation addons are blocked. Addons **must** declare interface version `120000` or higher in their `.toc` or they will not load (no player override).

---

### When Secrets Activate

Secrets are **not** always active. They engage under specific `AddOnRestrictionType` conditions:

| Restriction | Trigger |
|---|---|
| `Combat` | Player enters combat (`PLAYER_REGEN_DISABLED` timing) |
| `Encounter` | Instance encounter in progress |
| `ChallengeMode` | Mythic keystone run active |
| `PvPMatch` | PvP match active |
| `Map` | Inside an instance (for unit identity — names, GUIDs, IDs) |

Use `C_RestrictedActions.IsAddOnRestrictionActive(type)` and listen to `ADDON_RESTRICTION_STATE_CHANGED` to know when restrictions flip.

---

### Secret Aspects & Propagation

Secrets propagate through **Secret Aspects** — tagged groups of related APIs. Example: marking the "Shown" aspect on a frame makes `SetShown`, `IsShown`, and `IsVisible` all return secrets.

**Propagation rules:**
- Secrets propagate **downward** through frames anchored to a secret object.
- Secrets do **not** propagate upward to parent frames.
- Calling any API with secrets that applies a Text aspect to a FontString marks its anchoring as secret — all measurement/anchoring APIs then return secrets instead of erroring.
- `SetToDefaults()` clears all secret state and aspects from an object.

---

### What Tainted Code CANNOT Do

- **Compare** secrets to any value (`if secretVal == 100` → error)
- **Arithmetic** on secrets (`secretVal + 1` → error)
- **Conditional logic** on secrets (`if secretVal then` works only as nil-check — `type(x) ~= "nil"`)
- **`tonumber()`** on secret strings
- **Serialize** secrets into SavedVariables
- **Access combat log events** — `COMBAT_LOG_EVENT_UNFILTERED` is completely removed from addon access
- **Parse combat log chat messages** — converted to **KStrings** (special unparseable string type)
- **Send addon communications** during restricted contexts (M+ keystones, PvP matches, encounter in progress)
- **Send chat messages** during those same restricted contexts
- **Read** unit names, GUIDs, or creature IDs while in an instance (Map restriction, not combat-dependent)

---

### What Tainted Code CAN Do

- **Pass secrets to APIs designed to accept them** (see list below)
- **`string.format()` / concatenation** with secrets — result inherits secret state
- **`SetAlphaFromBoolean(bool, alphaIfTrue, alphaIfFalse)`** — converts boolean secret to visual property
- **`SetVertexColorFromBoolean()`** — colours regions based on boolean secrets
- **`ColorCurve` objects** — map health %/aura duration to colours without inspecting values
- **`StatusBar:SetValue()`** with `Enum.StatusBarInterpolation.ExponentialEaseOut`
- **`Cooldown:SetCooldownFromExpirationTime(expTime, duration, modRate)`** — display cooldown bars
- **Access player's own spellcast info** (non-secret even in combat)
- **Access secondary resources** — combo points, runes, soul shards, holy power, chi, arcane charges, essence, stagger (all non-secret for the player)
- **`UnitHealthMax()` / `UnitPowerMax()`** — non-secret for the player unit
- **Aura instance IDs** — non-secret (but aura contents are secret)
- **`UnitIsUnit()` comparisons** against target, focus, mouseover, softenemy, softinteract, softfriend — relaxed to return non-secret values

---

### APIs That Return Secrets (When Restricted)

| API | When Secret |
|---|---|
| `UnitHealth()`, `UnitHealthMax()`, `UnitHealthPercent()`, `UnitHealthMissing()` | Combat / Encounter / M+ / PvP (except player's own max) |
| `UnitPower()`, `UnitPowerMax()`, `UnitPowerPercent()`, `UnitPowerMissing()` | Same (except player's own max; returns 0 for unavailable types) |
| Unit names, GUIDs, creature IDs | Inside instances (Map restriction) |
| Aura data (buff/debuff values) | Combat / Encounter / M+ / PvP (instance IDs stay non-secret) |
| Cooldown durations | M+ / PvP / Encounter / Combat |
| `UNIT_SPELLCAST_SENT` target name | When restricted |
| `GetText()` on secure FontStrings | When those FontStrings are read during secure execution |

---

### APIs That Accept Secrets

| API | Notes |
|---|---|
| `StatusBar:SetValue()` | With interpolation enum |
| `SetAlphaFromBoolean()` | Region method — bool → alpha |
| `SetVertexColorFromBoolean()` | FontString/Texture method — bool → colour |
| `string.format()`, `string.join()` | Result inherits secret state |
| `AbbreviateNumbers()`, `AbbreviateLargeNumbers()` | Result inherits secret state |
| `WrapTextInColorCode()` | Result inherits secret state |
| `C_StringUtil.TruncateWhenZero(n)` | Returns secret string if > 0, empty if 0 |
| `C_StringUtil.WrapString(infix, prefix, suffix)` | Conditional concatenation |
| `SetTexture()` | Accepts secret **numbers** — NOT secret strings |
| `SetRotation()` | Applies Rotation secret aspect |
| `SetSpriteSheetCell()` | Accepts secret cell values (up to 256) |
| `Cooldown:SetCooldownFromExpirationTime()` | For addon cooldown bar display |
| `Cooldown:SetCooldownFromDurationObject()` | Type-safe cooldown setting |
| `StatusBar:SetTimerDuration()` / timer APIs | Self-updating timer bars |

---

### New Secret-Related APIs

**Inspection:**
- `issecretvalue(v)`, `issecrettable(t)` — identify secret data
- `canaccessvalue(v)`, `canaccesstable(t)`, `canaccessallvalues(...)` — check access
- `secretwrap(v)` — manually wrap a value as secret
- `scrubsecretvalues(...)` — strip secrets from arguments
- `hasanysecretvalues(...)` — detect presence of any secrets
- `dropsecretaccess()` — relinquish access rights

**Restriction state queries:**
- `C_Secrets.HasSecretRestrictions()` — are any restrictions active?
- `C_Secrets.ShouldCooldownsBeSecret()`, `ShouldAurasBeSecret()`, `ShouldUnitPowerBeSecret()`, `ShouldUnitHealthMaxBeSecret()`, `ShouldUnitIdentityBeSecret()`, `ShouldUnitSpellCastBeSecret()`, `ShouldUnitComparisonBeSecret()`, `ShouldSpellCooldownBeSecret()`, `ShouldUnitAuraBeSecret()` — per-category checks

**Frame-level:**
- `frame:HasSecretValues()`, `HasSecretAspect()`, `HasAnySecretAspect()`
- `frame:SetPreventSecretValues()`, `IsPreventingSecretValues()`
- `frame:IsAnchoringSecret()` — detect if positioning is restricted

**Events:**
- `ADDON_RESTRICTION_STATE_CHANGED` — fires when any restriction type changes

---

### hooksecurefunc Rules

**Always hook instances, never mixin tables:**
```lua
-- SAFE: C-level wrapper on the frame instance
hooksecurefunc(frame, "Method", hook)

-- DANGEROUS: Mixin() copies the hooked function as a plain Lua value.
-- The copy loses its C-level metadata, so securecallfunction runs
-- everything insecurely → secret values everywhere.
hooksecurefunc(MixinTable, "Method", hook)  -- NEVER DO THIS
```

**Banned function names (12.0+):** Attempting to hook these raises `"Cannot hook function"`:
`getfenv`, `rawset`, `select`, `getmetatable`, `pairs`, `setfenv`, `pcall`, `setmetatable`, `ipairs`, `pcallwithenv`, `type`, `issecurevalue`, `scrub`, `unpack`, `issecurevariable`, `securecall`, `wipe`, `next`, `securecallfunction`, `xpcall`, `rawget`, `secureexecuterange`

**Behaviour:**
- Multiple `hooksecurefunc()` calls on the same function **stack** (all run)
- No unhooking — only a UI reload removes hooks
- `setfenv()` throws errors on hooked functions
- For frame script handlers, prefer `Frame:HookScript()` over `hooksecurefunc`

---

### UI Skinning Safe Practices

#### DO (Safe)

- **Child frames for backdrops:** `CreateFrame("Frame", nil, parent, "BackdropTemplate")` — addon-owned frame, safe to call `SetBackdrop`, `SetBackdropColor`, etc.
- **External tracking tables:** `local skinnedFrames = {}` — never write custom keys onto Blizzard frame tables.
- **Visual property modifications on Blizzard frames:** `SetStatusBarTexture`, `SetAtlas`, `SetTexture`, `Hide`, `SetAlpha(0)`, `ClearAllPoints`, `SetPoint` — these taint only the specific property they touch.
- **Hook `ScrollBox.Update` on instances** to skin entries after all secure Init calls finish. Iterate with `ForEachFrame`.
- **Alpha-zero suppression pattern:**
  ```lua
  region:SetAlpha(0)
  hooksecurefunc(region, "SetAlpha", function(self, a)
      if a ~= 0 then self:SetAlpha(0) end
  end)
  ```
- **`C_Timer.After(0, fn)`** to defer layout changes outside secure execution context.
- **Re-anchor instead of resize** — use `ClearAllPoints`/`SetPoint` as a safe alternative to `SetWidth`/`SetHeight` in hooks.

#### DON'T (Causes Taint)

- **Never `Mixin(blizzardFrame, BackdropTemplateMixin)`.** Writes tainted keys onto the Blizzard frame's table. Secure code encountering those keys gets tainted. Use `CreateFrame("Frame", nil, parent, "BackdropTemplate")` instead.
- **Never `hooksecurefunc(MixinTable, "Method", hook)`.** See hooksecurefunc section above.
- **Never `SetHeight`/`SetWidth`/`SetSize` on Blizzard frames inside hooks** to secure frames. Triggers layout cascades that cause `Refresh` to re-enter in the addon's tainted context.
- **Never `SetFont` on FontStrings read during secure execution** (e.g. `statusBar.Name`, `statusBar.Value`, `window.NotActive`, `window.SessionTimer`). Taints the FontString → `GetText()` returns secret values in secure code.
- **Never modify layout properties** (`ClearAllPoints`/`SetPoint`) **synchronously** on frames evaluated during secure `Refresh`. Use `C_Timer.After(0, ...)` to defer.
- **Never write custom keys to Blizzard frames** (e.g. `blizzardFrame._myFlag = true`). Use external tracking tables.
- **Never pass secret `widgetSizeSetting` into `SetWidth`** — causes protected-index violations.
- **Never use `BackdropTemplate` directly on tooltips** shown via `securecallfunction`. `BackdropTemplate`'s `SetupTextureCoordinates` calls `GetWidth()` in Lua, which returns a secret value in that context. Use a plain frame + `CreateTexture` + `SetColorTexture` instead.

---

### Combat Log Replacement

| Old | New |
|---|---|
| `COMBAT_LOG_EVENT_UNFILTERED` | Completely removed from addon access |
| Parseable chat log messages | Converted to KStrings (unparseable) |
| Addon damage meters | Built-in Damage Meter (`C_DamageMeter` namespace) |
| `CombatLogAddFilter()`, etc. | `C_CombatLog.ApplyFilterSettings()`, etc. |

**New events:** `COMBAT_LOG_EVENT_INTERNAL_UNFILTERED`, `COMBAT_LOG_MESSAGE`, `DAMAGE_METER_COMBAT_SESSION_UPDATED`, `DAMAGE_METER_RESET`

**New APIs:** `C_DamageMeter.GetAvailableCombatSessions()`, `GetCombatSessionFromID()`

---

### Testing & Debugging

**CVars** (non-persistent, for local testing):
`secretAurasForced`, `secretCooldownsForced`, `secretUnitIdentityForced`, `secretSpellcastsForced`, `secretUnitPowerForced`, `secretUnitPowerMaxForced`, `secretUnitComparisonForced`, `addonChatRestrictionsForced`

**Test encounter:** MOTHERLODE!! dungeon has spell-spamming units for testing without a real group.

**`/dump`** prints secret value contents to chat for inspection.

**Blizzard can flag specific spells as "never secret":** Profession spells, Dragonriding/Skyriding spells, and others at developer discretion.
