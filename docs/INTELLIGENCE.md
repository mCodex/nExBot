# Adaptive Intelligence

nExBot uses one local intelligence runtime for target arbitration, combat movement, CaveBot route state, online learning, replay, and diagnostics. It does not require a server component or external machine-learning service.

## Tactical flow

```text
client callbacks -> EventBus -> normalized events
UnifiedTick -> immutable world snapshot -> centralized features
TargetBot and tactical states -> proposals -> Decision Engine -> Hard Safety
                                               |-> AttackStateMachine
                                               `-> MovementCoordinator
outcomes -> replay, metrics, calibration, resources, loot, and local models
```

The runtime creates one indexed world snapshot per scheduled generation. TargetBot, Dynamic Lure, Pull, Wave/Beam Avoidance, and CaveBot route recovery use the same generation numbers, so delayed work cannot act on a replaced target or route.

## Decision safety

The Decision Engine processes proposals in this order:

1. Reject expired, stale, malformed, or invalid proposals.
2. Apply the hard safety envelope.
3. Resolve ownership and contradictory actions.
4. Rank valid proposals by safety, priority, confidence, and utility.
5. Send one command to AttackStateMachine or MovementCoordinator.

AttackStateMachine is the autonomous native attack issuer. MovementCoordinator arbitrates TargetBot tactical movement, ChaseController owns native chase-mode writes, and CaveBot keeps deterministic ownership of validated waypoint paths.

## Tactical state machines

| Feature | Inputs | Output |
|---------|--------|--------|
| Dynamic Lure | Creature count, configured bounds, delay, safety evidence | Collect, hold, complete, or abort proposal |
| Pull | Participant, distance, timeout, route state | Pull, hold, complete, or abort proposal |
| Wave/Beam | Direction, timing, confidence, safe-tile result | Avoidance proposal with hysteresis |
| CaveBot route | Waypoint, pause reason, path and recovery outcomes | Generation-safe route transition |

These state machines submit proposals. They do not call native movement APIs.

## Local models

nExBot registers twelve bounded models:

| Model | Learns |
|-------|--------|
| MonsterBehaviorModel | Creature behavior outcomes |
| WavePredictionModel | Wave prediction success |
| TargetUtilityModel | Target selection outcome |
| TargetSwitchModel | Target-switch quality |
| LureSafetyModel | Lure safety outcome |
| PullContinuationModel | Pull completion outcome |
| RouteReliabilityModel | Route movement success |
| NavigationCostModel | Decaying route penalties |
| ResourceEfficiencyModel | Resource cost per outcome |
| CombatAreaModel | Area combat outcome |
| ObservationQualityModel | Sample reliability |
| LatencyModel | Latency class and confidence |

### Operating modes

| Mode | Observes | Predicts | Changes actions |
|------|----------|----------|-----------------|
| `OFF` | No | No | No |
| `OBSERVE` | Yes | No | No |
| `SHADOW` | Yes | Yes | No |
| `ACTIVE` | Yes | Yes | Yes, within hard safety bounds |

All models start in `SHADOW`. Promotion requires enough evidence, confidence, acceptable calibration error, available CPU budget, no safety regression, and no XP, path-failure, or target-thrashing regression. Rollback returns a model to `SHADOW`.

## Configuration precedence

nExBot applies behavior in this order:

1. Character configuration, selected CaveBot route, and TargetBot monster profile
2. Deterministic path validity, attack state, and hard safety
3. Context adjustment for the same route and monster profile
4. Global model evidence

Configured target priority ranks before every learned score. Learning cannot enable chase, change keep-distance settings, replace a waypoint, expand lure limits, or bypass reachability. It can adjust a valid candidate's score or recovery cost by at most 10 percent.

Each character stores separate summaries because UnifiedStorage is per-character. The context key combines the selected CaveBot route and TargetBot monster profile. A new context records 30 outcomes in shadow before its adjustment becomes actionable. Context confidence must reach 0.7. The runtime keeps at most 128 summaries and caps each summary at 1,000 samples.

## Replay and calibration

Replay stores normalized events, snapshot references, features, proposals, selections, rejections, outcomes, and rewards. It accepts serializable Lua values, rejects incompatible schema versions, strips runtime userdata, and keeps a fixed record limit.

Calibration compares predicted probability with observed outcomes in bounded buckets. Attack and movement outcomes update the related model and calibration record through EventBus adapters.

## Resources, XP, and loot

Heal spells, potions, runes, combat time, damage, XP gain, recovery, and loot messages feed bounded observers. The reward model combines XP, time, resource cost, safety, and recovery. Loot capture does not assign a universal value to an item.

## Performance controls

The runtime selects an idle, route, combat, or emergency snapshot interval. When a measured tick exceeds its budget, it disables optional work in this order:

1. Diagnostics
2. Replay
3. Learning
4. Neural inference
5. Route alternatives

Hard safety and command execution remain enabled. See [Performance](PERFORMANCE.md) for current benchmark results and complexity notes.

## Tactical Intelligence window

Open **nExBot Tactical Intelligence** from the Main tab. The window includes:

- Overview and lifecycle
- Targeting, Dynamic Lure, Pull, and Wave Avoidance
- CaveBot Intelligence and navigation profiles
- Model modes and monster profiles
- Resource efficiency and replay counts
- Bot Doctor diagnostics and performance status

The presenter uses one-column touch layout on small screens and the same state model on desktop, mobile, and web builds.

## Persistence and migration

UnifiedStorage keeps settings under `intelligence`. Migration copies the selected TargetBot JSON profile and preserves the CaveBot CFG as raw content. It excludes transient combat, current target, current path, replay, diagnostics, and old learned runtime state. Migration runs once per character and keeps existing user settings. New context learning persists bounded route and monster summaries separately from user configuration.

Model state includes schema and feature versions. Incompatible state resets that model without resetting TargetBot or CaveBot configuration.

## Bot Doctor

Bot Doctor checks:

- Movement and attack ownership
- Active lifecycle subscriptions
- UnifiedStorage and replay schema versions
- Measured UnifiedTick time against the intelligence budget

Open **Diagnostics** in the Tactical Intelligence window. Each issue includes a code, explanation, and corrective action.
