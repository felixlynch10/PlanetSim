# PlanetSim Improvement Plan

## Overview
Transform PlanetSim from a basic orbital simulator into an interactive educational tool for learning about gravity, orbits, and celestial mechanics. All changes build on the existing architecture (SwiftUI Canvas, SIMD3 physics, Velocity Verlet integration).

---

## Phase 1: Core UX & Visibility Improvements
*Make the app immediately understandable and navigable.*

### 1.1 Always-Visible Body Labels
- **File:** `OrbitCanvasView.swift` — `drawBody()`
- Add a toggle `@State private var showLabels: Bool = true`
- When enabled, draw planet name below each body (not just when selected)
- Use smaller font (9pt) with slight opacity so it doesn't clutter
- Selected body keeps the current larger label style

### 1.2 Elapsed Time Display
- **File:** `GravitySimulation.swift` — add a computed `elapsedTimeString` property
- Track `startDate` alongside `simulationTime`, compute delta
- Format as human-readable: "Day 14", "Year 2, Day 103", etc. (using 365.25-day years)
- **File:** `OrbitCanvasView.swift` — `timeControls`
- Display elapsed time next to the speed slider

### 1.3 Onboarding Overlay
- **New file:** `Views/OnboardingOverlay.swift`
- Semi-transparent overlay shown on first launch (persisted via `@AppStorage`)
- Key hints: "Scroll to zoom", "Drag to rotate", "Click a planet to inspect", "Use Launch Object to add bodies"
- Dismiss button or auto-dismiss on first interaction
- Keep it minimal — 4-5 short lines with small icons

### 1.4 Zoom to Fit Button
- **File:** `OrbitCanvasView.swift`
- Add a button in `timeControls` bar
- Calculate bounding box of all body positions (projected to screen)
- Set `logZoom` so all bodies fit within 80% of the canvas
- Animate the zoom transition with `withAnimation`

---

## Phase 2: Educational Visualizations
*Show the physics, don't just simulate them.*

### 2.1 Gravity Force Vectors
- **File:** `OrbitCanvasView.swift` — new `drawForceVectors()` method
- Add toggle: `@State private var showForceVectors: Bool = false`
- For each body, compute net gravitational force vector (already have `computeAccelerations()` logic)
- Draw as an arrow from the body in the force direction
- Scale arrow length logarithmically so small and large forces are both visible
- Color: white with opacity, or gradient from body color to white
- **File:** `GravitySimulation.swift` — expose `computeAccelerations()` as public (currently private)
- Add toggle button to the controls bar or sidebar

### 2.2 Orbit Path Prediction (Keplerian Ellipse)
- **File:** `GravitySimulation.swift` — new `predictOrbit(bodyIndex:)` method
- For each planet, compute the osculating Keplerian orbit relative to the dominant mass (star)
- Return an array of points tracing the predicted ellipse
- **File:** `OrbitCanvasView.swift` — new `drawPredictedOrbit()` method
- Draw as a faint dashed ellipse in the body's color
- Toggle: `@State private var showOrbits: Bool = false`
- Only show for the selected body or all bodies (user toggle)

### 2.3 Energy & Orbit Type Indicator
- **File:** `GravitySimulation.swift` — new computed properties per body:
  - `kineticEnergy(index:)` = 0.5 * m * v^2
  - `potentialEnergy(index:)` = sum of -G*m*M/r for all other bodies
  - `totalMechanicalEnergy(index:)` = KE + PE
  - `isEscaping(index:)` = totalEnergy >= 0
  - `orbitalPeriod(index:)` — from semi-major axis of osculating orbit
- **File:** `SidebarView.swift` — `BodyRowView` expanded section
- Add new rows: "Orbital Energy", "Type: Bound/Escape", "Est. Period"
- Color-code: green for stable orbit, red/orange for escape trajectory
- Show for launched objects too — immediate feedback on whether your launch captured or escaped

### 2.4 Gravitational Field Heatmap (Optional/Advanced)
- **New file:** `Views/GravityFieldOverlay.swift`
- Toggle to show a background heatmap of gravitational potential
- Sample a grid of points across the visible canvas area
- Compute gravitational potential at each point, map to color (dark = weak, bright = strong)
- Use Metal or pre-rendered image for performance (Canvas drawing of a grid of small rects)
- This is computationally expensive — use a coarse grid (e.g., 40x40) and interpolate
- Only render when toggled on, recompute on zoom/pan changes with debounce

---

## Phase 3: Interactive Features
*Let users experiment and play.*

### 3.1 Follow Camera
- **File:** `OrbitCanvasView.swift`
- Add `@State private var followingBody: Int? = nil`
- When set, offset the projection center so the followed body is at screen center
- In `project()`, subtract the followed body's position before rotating
- Add "Follow" button in the sidebar body detail panel
- Double-click a body on canvas to toggle follow
- Show subtle indicator ("Following: Cerulea") in the controls bar
- Allow rotation/zoom while following

### 3.2 Collision Detection & Merging
- **File:** `GravitySimulation.swift`
- After each Verlet step, check pairwise distances
- Collision threshold: sum of display radii scaled to world units, or a physics-based Roche limit approximation
- On collision:
  - Merge masses (m1 + m2)
  - Conserve momentum: new velocity = (m1*v1 + m2*v2) / (m1+m2)
  - Position = center of mass
  - Larger body absorbs smaller (keep larger body's name/color, or blend)
  - Display radius = cbrt(r1^3 + r2^3) to conserve volume
- Remove the smaller body from the array, update trail arrays
- **New file:** `Views/CollisionEffectView.swift` (optional)
  - Brief particle burst animation at collision point
  - Can be drawn in Canvas as expanding/fading circles

### 3.3 Scenario Presets
- **New file:** `Models/ScenarioPresets.swift`
- Define preset configurations as static functions returning `[CelestialBody]`:
  - **Default** — current 6-planet system
  - **Binary Star** — two massive stars orbiting each other with 2-3 planets
  - **Heavy Jupiter** — default system but one planet is 10x mass (shows perturbation effects)
  - **Rogue Planet Flyby** — default + a massive body on a hyperbolic trajectory
  - **Inner System Only** — just 3 close planets for detailed observation
  - **Chaos** — 12+ equal-mass bodies in unstable orbits
- **File:** `SidebarView.swift`
- Add a "Scenarios" dropdown/picker above the object list
- Selecting a preset calls `simulation.loadScenario(bodies:)`
- **File:** `GravitySimulation.swift`
- Add `loadScenario(bodies: [CelestialBody])` that replaces current state

### 3.4 Improved Launch Experience
- **File:** `LaunchPanelView.swift`
- Add launch presets: "Circular Orbit" auto-calculates velocity for a circular orbit at the click point
- Show whether the current aim will result in a bound orbit or escape (real-time, using energy calc from 2.3)
- **File:** `OrbitCanvasView.swift`
- During aiming, color the trajectory preview green (bound) or red (escape)

---

## Phase 4: Info & Education Panels
*Teach the user what they're seeing.*

### 4.1 Planet Info Cards
- **File:** `SidebarView.swift` — expand `BodyRowView`
- New rows in the expanded detail section:
  - **Surface gravity** — g = G*M/r^2 (using displayRadius as proxy, with note)
  - **Orbital period** — computed from current osculating orbit
  - **Orbital velocity** — already shown, but add context: "1.2x Earth orbital speed"
  - **Hill sphere radius** — r * (m / 3M)^(1/3), shows gravitational influence region
- Add comparative text: "This planet's gravity is 3.2x Earth's" (using Earth = 9.8 m/s^2 as reference)

### 4.2 Physics Explainer Tooltips
- **New file:** `Views/TooltipView.swift`
- Small "?" icon next to each physics readout in the sidebar
- On hover, show a brief explanation:
  - "Orbital energy determines if an object is gravitationally bound (negative) or escaping (positive)"
  - "The Hill sphere is the region where this body's gravity dominates over the star's"
  - "Eccentricity measures how elliptical an orbit is: 0 = circle, 1 = parabolic escape"
- Implement as a popover or overlay anchored to the "?" button

### 4.3 Simulation Stats Bar
- **File:** `OrbitCanvasView.swift` — new overlay at top-right
- Show: body count, total system energy, elapsed time, substep count
- Helps users understand computational cost and conservation laws
- Subtle styling, small font, semi-transparent background

---

## Phase 5: Polish & Feel
*Make it feel premium.*

### 5.1 Smooth Animations
- Animate zoom changes (currently instant)
- Animate camera snapping when following a body
- Smooth sidebar expand/collapse (already has basic animation)

### 5.2 Visual Improvements
- Star glow effect: radial gradient around Solara instead of flat circle
- Body glow: subtle outer glow on planets proportional to mass
- Better trail rendering: use a gradient mesh or thicker trails for more massive bodies

### 5.3 Keyboard Shortcuts
- Space = play/pause
- R = reset
- F = follow selected
- L = toggle labels
- V = toggle force vectors
- O = toggle orbit predictions
- 1-9 = select body by index
- Esc = deselect / cancel launch
- **File:** `OrbitCanvasView.swift` or `ContentView.swift`
- Add `.onKeyPress` or keyboard event handling in `InputNSView`

### 5.4 Minimap (Optional)
- Small overview in the corner showing all bodies at a fixed zoom level
- Highlights the current viewport region
- Click to jump to a location

---

## Implementation Order

| Priority | Task | Effort | Files Changed |
|----------|------|--------|---------------|
| 1 | Always-visible labels (1.1) | Small | OrbitCanvasView |
| 2 | Elapsed time display (1.2) | Small | GravitySimulation, OrbitCanvasView |
| 3 | Keyboard shortcuts (5.3) | Small | OrbitCanvasView/InputNSView |
| 4 | Follow camera (3.1) | Medium | OrbitCanvasView, SidebarView |
| 5 | Force vectors (2.1) | Medium | OrbitCanvasView, GravitySimulation |
| 6 | Energy & orbit type (2.3) | Medium | GravitySimulation, SidebarView |
| 7 | Orbit prediction ellipses (2.2) | Medium | GravitySimulation, OrbitCanvasView |
| 8 | Collision detection (3.2) | Medium | GravitySimulation |
| 9 | Scenario presets (3.3) | Medium | New file, SidebarView, GravitySimulation |
| 10 | Planet info cards (4.1) | Small | SidebarView |
| 11 | Improved launch (3.4) | Medium | LaunchPanelView, OrbitCanvasView |
| 12 | Onboarding overlay (1.3) | Small | New file, ContentView |
| 13 | Zoom to fit (1.4) | Small | OrbitCanvasView |
| 14 | Star/body glow (5.2) | Small | OrbitCanvasView |
| 15 | Tooltips (4.2) | Small | New file, SidebarView |
| 16 | Stats bar (4.3) | Small | OrbitCanvasView |
| 17 | Gravity heatmap (2.4) | Large | New file |
| 18 | Minimap (5.4) | Medium | New file |

---

## Notes
- All physics stays in SI units (meters, kg, seconds)
- New toggles (labels, vectors, orbits) should persist via `@AppStorage`
- Performance-sensitive features (heatmap, force vectors with many bodies) need frame-time guards
- Collision detection must update `trailPoints3D` array indices correctly when removing bodies
- Follow camera needs to handle the followed body being removed (collision/reset)
