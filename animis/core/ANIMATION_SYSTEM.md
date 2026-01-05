# Animis V2 Animation System Documentation

## Overview

The V2 animation system is a priority-based state machine that handles multiple animation types with complex interaction rules. It supports state-based animations, input-triggered animations (toggle/hold/down), random animations, and chained animations with interrupt/resume capabilities.

## Core Concepts

### Priority Levels

The system uses a three-tier priority system:

```lua
PRIORITY_INPUT = 3   -- Input triggers (toggle/hold/down) - Highest
PRIORITY_RANDOM = 2  -- Random triggers - Can override state-based
PRIORITY_STATE = 1   -- State-based and defaults - Lowest
```

**Priority Rules:**
- Higher priority animations can interrupt lower priority animations
- Same priority animations do not interrupt each other
- Input triggers always have the highest priority
- Random animations can override state-based but not input-triggered
- State-based animations are the fallback when nothing else is active

### Animation Types

#### 1. State-Based Animations
- Triggered by player state (idle, walk, run, jump, etc.)
- Lowest priority (PRIORITY_STATE = 1)
- Defined with `states: ["idle", "walk"]` array
- No states specified = matches all states
- Examples: idle, walk, run animations

#### 2. Input-Triggered Animations
- Triggered by player input via keybinds
- Highest priority (PRIORITY_INPUT = 3)
- Three modes:
  - **toggle/switch**: Press to turn on, press again to turn off. Animation stays active until toggled off.
  - **hold**: Active while key is held down. Stops when key is released.
  - **down**: Triggers once on key press. Single-shot activation.

#### 3. Random Animations
- Triggered randomly based on chance and timing
- Medium priority (PRIORITY_RANDOM = 2)
- Defined with `triggers: [{type: "random", chance: 0.01, checkInterval: 1.0}]`
- Can specify states to trigger in, or no states to trigger in any state
- Default duration of 5 seconds for looping random animations (configurable)

#### 4. Internal Animations
- Part of a chain, inherit context from parent animation
- Marked with `internal: true`
- Do not have their own triggers
- Inherit `triggerBind` and `triggerMode` from parent for continuation validation
- Used for multi-stage animations (beforeloop → loop → afterloop)

## Update Flow (Four Sections)

Each frame, the system processes animations in four distinct sections:

### Section 1: Input Triggers (Priority 3 - Highest)

**Purpose:** Check if any input-triggered animations should start or continue.

**Process:**
1. Loop through all animations with input triggers
2. Check if the bound key matches the current state (bindDown/bind)
3. Handle toggle state flipping for toggle/switch mode
4. **Special case:** If toggling the currently playing animation, defer to Section 2
5. Start animation if:
   - Toggle is ON (for toggle/switch mode)
   - Key is held (for hold mode)
   - Key was just pressed (for down mode)
6. Respect interrupt/resume: if different input trigger is active, defer to Section 2

**Key Variables:**
- `layer.inputToggles[bind]` - Toggle state for each bind (true/false)
- `deferToggleToSection2` - Flag to skip to Section 2 for toggle state changes

**Returns:** If animation starts, exits immediately. Otherwise falls through.

---

### Section 2: Current Animation Continuation and Chaining

**Purpose:** Handle currently playing animation's lifecycle - continuation, chaining, and state changes.

**Process (in order):**

#### 2a. Non-Looping Animation Finished → Chain
```lua
if layer.animationFinished and anim.chainTo then
    playAnimation(chainTo)
    return
```
- When non-looping animation finishes, check for `chainTo`
- If chainTo exists, start the next animation in the chain
- Inherits priority from parent animation

#### 2b. Persist Across State Changes
```lua
if anim.persist and state != layer.startState then
    continueAnimation()
    return
```
- `persist: true` means animation ignores state changes
- Keeps playing even when player state changes (idle → walk → jump)

#### 2c. State Change Chains
```lua
if not anim.persist and state != layer.startState and anim.chainTo then
    playAnimation(chainTo)
    return
```
- If state changes and animation is NOT persist
- If `chainTo` exists, chain to next animation
- Allows state-dependent animation sequences

#### 2d. Duration Enforcement
```lua
if anim.duration then
    elapsed = now - layer.animStartTime
    if elapsed >= duration then
        // Chain or fallthrough
    else
        // Continue playing (duration not expired)
```
- **Duration expired:** Chain if available, otherwise skip to Section 3/4 (goto skipContinuation)
- **Duration not expired:** Force continuation regardless of other factors
- **Persist behavior:** `persist: true` means non-interruptible until duration expires
- **Without persist:** Duration still enforced, but can be interrupted by Section 1 input triggers

#### 2e. Input-Based Chains (Release/Toggle Off)
```lua
// For animations with triggers
if anim.chainTo and anim.triggers then
    if toggle mode and toggle is OFF: chainTo
    if hold mode and key released: chainTo
```
- Check if input condition changed (toggle off, key released)
- Chain to next animation when condition met
- Handles both animations with their own triggers AND internal animations with inherited triggers

**For internal animations (no triggers):**
```lua
if anim.chainTo and layer.triggerBind then
    if layer.triggerMode == "toggle/switch" and toggle OFF: chainTo
    if layer.triggerMode == "hold" and key released: chainTo
```
- Uses stored `layer.triggerBind` and `layer.triggerMode` from parent
- Allows chained animations to respect original trigger mode

#### 2f. Loop Continuation Validation
```lua
if not layer.animationFinished then
    stateMatches = check states, triggers, stored triggers
    if stateMatches or anim.persist:
        continueAnimation()
```
- Only runs if animation hasn't finished
- Validates multiple conditions:
  - **State match:** Does current state match animation's states?
  - **Input triggers:** For hold mode, is key still held? For toggle, is toggle still ON?
  - **Random triggers:** Set stateMatches = false if no duration (prevents infinite loops)
  - **Stored triggers:** For internal animations, check inherited trigger state
- **Persist override:** If `persist: true`, continue regardless of state match

#### 2g. Resume Interrupted Animation
```lua
if layer.interruptedAnim and layer.interruptedBind then
    if trigger still active:
        playAnimation(interruptedAnim)
```
- If an animation was interrupted by higher priority input
- Check if the interrupted animation's trigger is still active
- Resume it if still active, clear if not

**Returns:** If animation continues/chains/resumes, exits immediately. Otherwise falls through.

---

### Section 3: Random Triggers (Priority 2)

**Purpose:** Check if random animations should trigger.

**Process:**
1. Only runs if current animation priority < PRIORITY_RANDOM
2. Loop through all animations with random triggers
3. Check state match (or no states = always match)
4. Call `shouldTriggerRandom()` to check chance/interval/cooldown
5. Start random animation with PRIORITY_RANDOM

**Returns:** If random animation triggers, exits immediately. Otherwise falls through.

---

### Section 4: State-Based and Default Animations (Priority 1)

**Purpose:** Fallback to state-based or default animations.

**Process:**
1. Build list of animations matching current state
2. If no state matches, use animations with no states defined
3. Pick first matching animation
4. Start with PRIORITY_STATE

**Returns:** Starts state-based or default animation.

---

## Key State Variables

### Layer State (per animation layer: facial_hair, body, emote, hair)

```lua
layer.currentAnimName          -- Name of currently playing animation
layer.currentAnimData          -- Animation data table
layer.startState               -- Player state when animation started
layer.animStartTime            -- os.time() when animation started
layer.time                     -- Current frame time (1-based)
layer.previousTime             -- Last frame that was rendered
layer.animationFinished        -- Flag: non-looping animation reached end
layer.animPriority             -- Current animation priority (1-3)

-- Input Trigger State
layer.triggerBind              -- Input bind that started current animation chain
layer.triggerMode              -- Mode of trigger (toggle/switch/hold/down)
layer.inputToggles[bind]       -- Toggle on/off state for each bind

-- Interrupt/Resume State
layer.interruptedAnim          -- Name of animation that was interrupted
layer.interruptedBind          -- Bind of animation that was interrupted

-- Random Trigger State
layer.randomCooldowns[name]    -- Cooldown timer for each random animation
layer.randomChecks[name]       -- Next check time for each random animation
```

### Animation Data Properties

```lua
{
  "frames": ["directive1", "directive2", ...],  -- Frame directives
  "loop": true/false,                           -- Loop or stop at last frame
  "speed": 1.0,                                 -- Animation speed multiplier
  "states": ["idle", "walk"],                   -- Player states to trigger in
  "chainTo": "nextAnimName",                    -- Chain to this animation when done
  "internal": true/false,                       -- Is this part of a chain?
  "persist": true/false,                        -- Ignore state changes/interruptions?
  "duration": 5.0,                              -- Play for this many seconds
  "priority": 2,                                -- Override default priority
  
  "triggers": [{                                -- Trigger conditions
    "type": "input",
    "bind": "fullloop",
    "mode": "toggle"/"switch"/"hold"/"down"
  }, {
    "type": "random",
    "chance": 0.01,                             -- Probability per check
    "checkInterval": 1.0,                       -- Seconds between checks
    "cooldown": 10.0                            -- Seconds before can trigger again
  }]
}
```

## Special Behaviors

### Toggle/Switch Mode

**Mechanism:**
- Press button → Flip toggle state → Check if toggle is ON → Start animation
- Animation continues as long as toggle is ON
- Press button again → Flip toggle to OFF → Animation chains or falls through
- Toggle state persists across frames

**Special handling in Section 1:**
```lua
if currently playing this toggle animation:
    flip toggle state
    defer to Section 2  // Let Section 2 handle the state change
    goto continue_input
```
- Prevents re-triggering the same animation immediately
- Allows Section 2 to detect toggle OFF and chain properly

### Hold Mode

**Mechanism:**
- Key pressed → Start animation
- Every frame: Check if key still held → Continue
- Key released → Chain to next animation or stop

**No deferred state needed:**
- Hold animations return immediately in Section 1 if key is held
- Section 2 handles key release via input-based chains

### Chained Animations (Internal)

**Parent → Internal → Internal → ...**

Example: `beforeloop → fullloop → afterloop`
- `beforeloop`: Has input trigger, sets `layer.triggerBind` and `layer.triggerMode`
- `fullloop`: `internal: true`, inherits trigger context from beforeloop
- `afterloop`: `internal: true`, continues to use inherited trigger

**Inheritance:**
```lua
if hasInputTrigger:
    layer.triggerBind = t.bind        // Store for children
    layer.triggerMode = t.mode        // Store mode (toggle/hold)

if not hasInputTrigger and not anim.internal:
    layer.triggerBind = nil           // Clear when starting non-input animation
    layer.triggerMode = nil
```

**Validation in Section 2:**
```lua
// For internal animations without triggers
if not anim.triggers and layer.triggerBind:
    if triggerMode == "toggle/switch" and toggle OFF: stop
    if triggerMode == "hold" and key released: stop
```

### Interrupt/Resume System

**Purpose:** Allow high-priority inputs to temporarily interrupt lower-priority animations, then resume them.

**Mechanism:**
1. **Save on interrupt:**
```lua
if hasInputTrigger and layer.triggerBind and layer.currentAnimName:
    layer.interruptedAnim = layer.currentAnimName
    layer.interruptedBind = layer.triggerBind
```

2. **Resume when available:**
```lua
if layer.interruptedAnim and layer.interruptedBind:
    if trigger still active (toggle ON or key held):
        playAnimation(interruptedAnim)  // Resume
```

3. **Clear when no longer active:**
```lua
if trigger not active:
    layer.interruptedAnim = nil
    layer.interruptedBind = nil
```

**Example:**
- Playing: Hold animation A (hold key 1)
- Interrupt: Toggle animation B (press key 2, toggle ON)
- Animation A saved to interruptedAnim
- Playing: Toggle animation B
- Toggle OFF: Animation B stops
- Section 2g: Check if key 1 still held → Resume animation A

### Duration + Persist Interaction

**Duration only:**
```lua
duration: 5.0
// Can be interrupted by higher priority inputs (Section 1)
// But enforces 5 second minimum if not interrupted
```

**Duration + Persist:**
```lua
duration: 5.0
persist: true
// Cannot be interrupted - plays for full 5 seconds no matter what
// Ignores state changes too
```

**Use cases:**
- Random animation with duration, no persist: Plays for 5s or until input interrupt
- Cutscene animation with duration + persist: Guaranteed to play for full duration

### Random Animation Duration

**Default behavior:**
```lua
// In validateAnimation()
if anim.triggers (random) and anim.duration == nil and anim.loop:
    anim.duration = 5.0  // Auto-add 5 second duration
```

**Reason:**
- Prevents random looping animations from playing forever
- Can be overridden by setting explicit duration
- Non-looping random animations don't get auto-duration

### State Cleanup

**When starting state-based animations:**
```lua
if not hasInputTrigger and not anim.internal:
    layer.triggerBind = nil
    layer.triggerMode = nil
    layer.interruptedAnim = nil
    layer.interruptedBind = nil
```

**Purpose:**
- State-based animations override input triggers
- Clear all input trigger context when switching to state-based
- Prevents stale state from affecting future animations

## Directive Modifiers

**System:** Apply custom directives at runtime without modifying animation data.

**Mechanism:**
```lua
function applyDirectiveModifiers(directive)
    if os.__animisPrefix then
        directive = os.__animisPrefix .. directive
    if os.__animisSuffix then
        directive = directive .. os.__animisSuffix
    return directive
```

**Applied in:**
- `playAnimation()` when setting new frame
- `continueAnimation()` when advancing frame

**Usage:**
```lua
os.__animisPrefix = "?multiply=ff0000"    // Red tint
os.__animisSuffix = "?border=1;fff;000"   // White border
```

**Use cases:**
- Dynamic color effects
- Debugging animations (add visible borders)
- Temporary visual effects
- Mod compatibility layers

## Common Patterns

### Simple Toggle Animation
```json
{
  "frames": ["frame1", "frame2"],
  "loop": false,
  "triggers": [{
    "type": "input",
    "bind": "myToggle",
    "mode": "toggle"
  }]
}
```
- Press button → Play frames → Stay on last frame
- Press again → Return to idle

### Toggle with Before/Loop/After
```json
{
  "beforeloop": {
    "frames": ["transition in"],
    "loop": false,
    "chainTo": "loop",
    "triggers": [{"type": "input", "bind": "myToggle", "mode": "toggle"}]
  },
  "loop": {
    "frames": ["loop1", "loop2"],
    "loop": true,
    "internal": true,
    "chainTo": "afterloop"
  },
  "afterloop": {
    "frames": ["transition out"],
    "loop": false,
    "internal": true
  }
}
```
- Press button → beforeloop → loop (while toggled on) → afterloop (when toggled off)

### Random Animation with Duration
```json
{
  "frames": ["blink1", "blink2"],
  "loop": false,
  "triggers": [{
    "type": "random",
    "chance": 0.01,
    "checkInterval": 1.0,
    "cooldown": 5.0
  }],
  "duration": 2.0
}
```
- Randomly triggers with 1% chance every second
- Plays for 2 seconds
- Can be interrupted by input triggers
- Cooldown of 5 seconds before can trigger again

### Hold Animation
```json
{
  "frames": ["holding"],
  "loop": true,
  "triggers": [{
    "type": "input",
    "bind": "myHold",
    "mode": "hold"
  }]
}
```
- Loops while key is held
- Stops immediately when key is released

## Debugging Tips

### Enable Debug Logging
Check `config.DEBUG` flag to enable extensive logging:
- Animation starts/stops
- State changes
- Duration checks
- Chain triggers
- Input trigger candidates

### Common Issues

**Animation won't stop:**
- Check if it's a toggle/switch mode → Need to toggle OFF
- Check if persist: true → Can't be interrupted
- Check if duration not expired → Will continue until duration ends

**Animation won't trigger:**
- Check priority → Higher priority animation might be blocking
- Check state match → Animation states might not include current state
- Check input binding → Bind name might not match

**Animation chains incorrectly:**
- Check chainTo spelling → Must match animation name exactly
- Check internal flag → Chained animations should have internal: true
- Check trigger inheritance → Internal animations use parent's trigger

**Random animation loops forever:**
- Add duration property or let auto-duration apply
- Check if loop: true with no duration → Will loop forever without duration

## Performance Considerations

- Input checking happens every frame (16-60ms)
- Random checking respects checkInterval (typically 1 second)
- State changes trigger immediate re-evaluation
- Cooldowns prevent spam of random animations
- Priority system prevents unnecessary animation switches

## Version History

**V2 Features:**
- Priority-based animation system
- Input trigger modes (toggle/hold/down)
- Interrupt/resume system
- Duration enforcement with persist
- Random animation improvements
- Chained animation support with internal flag
- Directive modifiers (prefix/suffix)

**V1 → V2 Migration:**
- Old system: Single priority level, simpler state machine
- New system: Three priority levels, complex interaction rules
- Added: Input triggers, random triggers, chaining, interrupt/resume
