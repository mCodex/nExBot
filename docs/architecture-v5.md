# nExBot v5 — Architecture Document

## Overview

Clean layered architecture for deterministic combat decision-making with bounded ML assistance.

```
┌─────────────────────────────────────────────────────┐
│  INFRASTRUCTURE (Game API adapters)                 │
│  GameClientAdapter · MapAdapter · EventBridge       │
├─────────────────────────────────────────────────────┤
│  APPLICATION (State machines, orchestration)        │
│  AttackFSM (8 states, gen tokens, sole attack owner)│
│  MovementArbitrator (sole movement owner)           │
│  CombatDecisionFrame (immutable per-tick record)    │
│  TargetBotLoop (thin orchestrator)                  │
├─────────────────────────────────────────────────────┤
│  DOMAIN (Pure decision functions)                   │
│  TargetCommitmentManager · ReachabilityService      │
│  TargetCandidateEvaluator · FeatureArbitrator       │
│  ReleaseReasons · ReachabilityStates                │
├─────────────────────────────────────────────────────┤
│  TACTICAL (Executable planners)                     │
│  LurePlanner · DynamicLurePlanner                   │
│  PullPlanner · RepositionPlanner                    │
├─────────────────────────────────────────────────────┤
│  ML (Contextual models + governance)                │
│  KillCompletionModel · TargetSwitchRiskModel        │
│  LureSuccessModel · PullSuccessModel                │
│  RepositionTileModel · ContextualFeatureExtractor   │
└─────────────────────────────────────────────────────┘
```

## Ownership

| Responsibility | Owner |
|---------------|-------|
| Attack commands (g_game.attack) | AttackFSM |
| Attack cancellation | AttackFSM (RELEASING state only) |
| Movement commands | MovementArbitrator |
| Target selection | TargetCandidateEvaluator |
| CaveBot route progression | CaveBot (gated by commitment) |
| Tactical Intelligence | FeatureArbitrator |
| ML training/promotion | Intelligence pipeline (SHADOW default) |

## Module Reference

### Domain Layer

| Module | File | Responsibility |
|--------|------|---------------|
| ReleaseReason | `targetbot/domain/release_reasons.lua` | Valid release reason enum + validation |
| ReachabilityState | `targetbot/domain/reachability_states.lua` | 9-state reachability enum |
| ReachabilityService | `targetbot/domain/reachability_service.lua` | Multi-state evaluation with evidence accumulation |
| TargetCommitmentManager | `targetbot/domain/target_commitment.lua` | Formal target lease system |
| TargetCandidateEvaluator | `targetbot/domain/target_evaluator.lua` | Structured lexicographic scoring |
| FeatureArbitrator | `targetbot/domain/feature_arbitrator.lua` | Feature compatibility matrix + intent resolution |

### Application Layer

| Module | File | Responsibility |
|--------|------|---------------|
| AttackFSM | `targetbot/application/attack_fsm.lua` | 8-state FSM, sole attack owner, generation tokens |
| MovementArbitrator | `targetbot/application/movement_arbitrator.lua` | Sole movement owner, commitment-aware |
| CombatFrameRecorder | `targetbot/application/combat_frame.lua` | Bounded decision frame recording (256 ring buffer) |

### Tactical Layer

| Module | File | Responsibility |
|--------|------|---------------|
| LurePlanner | `targetbot/tactical/lure_planner.lua` | Executable lure plans with progress tracking |
| DynamicLurePlanner | `targetbot/tactical/dynamic_lure_planner.lua` | State machine with participant tracking + hysteresis |
| PullPlanner | `targetbot/tactical/pull_planner.lua` | Executable pull plans requiring destination+path |
| RepositionPlanner | `targetbot/tactical/reposition_planner.lua` | Attack-ring tile search with scoring |

### ML Layer

| Module | File | Responsibility |
|--------|------|---------------|
| ContextualFeatures | `targetbot/ml/contextual_features.lua` | Combat feature extraction |
| KillCompletionModel | `targetbot/ml/kill_completion_model.lua` | P(target dies within N ms) |
| TargetSwitchRiskModel | `targetbot/ml/target_switch_risk_model.lua` | P(target alive after switch) |
| LureSuccessModel | `targetbot/ml/lure_success_model.lua` | P(lure formation safe) |
| PullSuccessModel | `targetbot/ml/pull_success_model.lua` | P(creature follows) |
| RepositionTileModel | `targetbot/ml/reposition_tile_model.lua` | Tile ranking |

## AttackFSM States

```
IDLE → ACQUIRING → ATTACKING → CONFIRMING_ATTACK → LOCKED
                                    ↓                    ↓
                              REPOSITIONING      TEMPORARILY_BLOCKED
                                    ↓                    ↓
                              RECOVERING_TARGET    RELEASING → IDLE
```

Generation tokens prevent stale callbacks. Failed replacement candidates are rejected without touching the current target.

## Reachability States

| State | Release Target? | Action |
|-------|----------------|--------|
| ATTACKABLE_NOW | No | Continue attacking |
| REPOSITION_REQUIRED | No | Request repositioning |
| TEMPORARILY_BLOCKED | No | Retry after interval |
| VISIBILITY_UNKNOWN | No | Retry or reposition |
| PATH_API_UNAVAILABLE | No | Retry |
| MOVING_TARGET | No | Track and retry |
| DIFFERENT_FLOOR | **Yes** | Release immediately |
| REMOVED | **Yes** | Release immediately |
| CONFIRMED_HARD_UNREACHABLE | **Yes** | Release (requires 3+ evidence) |

## Feature Compatibility Matrix

| | FinishKill | Lure | DynLure | Pull | Reposition | Chase | KeepDist | WaveAvoid | Follow | CaveBot |
|---|---|---|---|---|---|---|---|---|---|---|
| **FinishKill** | — | HARD | HARD | HARD | COMPAT | COMPAT | COMPAT | MERGE | PREEMPT | HARD |
| **Lure** | HARD | — | MUTEX | COMPAT | COMPAT | COMPAT | MERGE | MERGE | PREEMPT | COMPAT |
| **Pull** | HARD | COMPAT | MUTEX | — | COMPAT | COMPAT | MERGE | MERGE | PREEMPT | PREEMPT |

Precedence: HARD_SAFETY > MANUAL > FINISH_KILL > ATTACK_CONTINUITY > WAVE_AVOIDANCE > REPOSITION > PULL > DYNAMIC_LURE > LURE > KEEP_DISTANCE > CHASE > ROUTE > ML

## ML Governance

- All models default to **SHADOW mode** (predictions logged, not used)
- Promotion requires: 100+ samples, calibration error < 0.1
- Rollback triggers: unfinished-target rate increase, target switch frequency increase
- TargetSwitchRiskModel returns 1.0 risk when commitment active (hard override)
- ML never overrides: safety constraints, commitments, manual overrides
