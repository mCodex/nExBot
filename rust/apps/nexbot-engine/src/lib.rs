pub mod combat_runtime;
pub mod healing;
pub mod inventory_runtime;
pub mod movement_runtime;
pub mod navigation;
pub mod route;

mod preview;

use preview::Preview;

use serde::{Deserialize, Serialize};
use subtle::ConstantTimeEq;

pub const MAX_FRAME: usize = 4096;
pub const PROTOCOL: u8 = 1;
pub const BRIDGE_VERSION: &str = "5.0.0-alpha.1";

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Eq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Position {
    pub x: u16,
    pub y: u16,
    pub z: u8,
}

impl Position {
    fn distance(self, other: Self) -> Option<u16> {
        (self.z == other.z).then(|| self.x.abs_diff(other.x).max(self.y.abs_diff(other.y)))
    }

    fn adjacent(self) -> Self {
        let x = if self.x == u16::MAX {
            self.x - 1
        } else {
            self.x + 1
        };
        Self { x, ..self }
    }
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct ContainerMetrics {
    pub elapsed_ms: u32,
    pub requests: u32,
    pub timeouts: u32,
    pub samples: u32,
    pub ack_ms: u32,
    pub max_ack_ms: u32,
}

impl ContainerMetrics {
    fn valid(&self) -> bool {
        self.samples.saturating_add(self.timeouts) <= self.requests
            && self.ack_ms <= self.elapsed_ms
            && self.max_ack_ms <= self.ack_ms
            && u64::from(self.ack_ms) <= u64::from(self.samples) * u64::from(self.max_ack_ms)
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize)]
pub struct LootTotals {
    pub reports: u32,
    pub nonempty: u32,
}

impl LootTotals {
    fn record(&mut self, nonempty: bool) {
        self.reports = self.reports.saturating_add(1);
        self.nonempty = self.nonempty.saturating_add(u32::from(nonempty));
    }
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum ClientFrame {
    Hello {
        protocol: u8,
        token: String,
        bridge_version: String,
        path_probe: bool,
    },
    Snapshot {
        sequence: u32,
        position: Position,
    },
    Move {
        sequence: u32,
        position: Position,
    },
    CreatureMove {
        sequence: u32,
        id: u32,
        position: Position,
    },
    HealComparison {
        sequence: u32,
        hp: u16,
        mp: u16,
        mana: u32,
        rules: Vec<healing::Rule>,
        selected: Option<usize>,
    },
    HealDispatch {
        sequence: u32,
        elapsed_ms: u32,
        #[serde(default)]
        echo: bool,
    },
    SupplyRefill {
        sequence: u32,
        stock: Vec<(u16, u32, u32)>,
    },
    LootReport {
        sequence: u32,
        monster: String,
        nonempty: bool,
    },
    ContainerMetrics {
        sequence: u32,
        metrics: ContainerMetrics,
    },
    FiringShadow {
        sequence: u32,
        target: Position,
        min: u16,
        max: u16,
        selected: Position,
        positions: Vec<(Position, u32)>,
    },
    TargetShadow {
        sequence: u32,
        selected: Option<u32>,
        current: Option<u32>,
        candidates: Vec<navigation::TargetCandidate>,
    },
    Tile {
        sequence: u32,
        position: Position,
        walkable: Option<bool>,
        ignore_creatures: Option<bool>,
    },
    RouteGoal {
        sequence: u32,
        position: Option<Position>,
    },
    RouteAck {
        sequence: u32,
        id: u32,
        directions: Option<Vec<u8>>,
    },
    Ack {
        sequence: u32,
        id: u32,
        path_result: Option<u8>,
    },
}

#[derive(Debug, PartialEq, Eq, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ServerFrame {
    Ready {
        proof: String,
        protocol: u8,
        cave_shadow: bool,
        heal_timing: bool,
        target_shadow: bool,
        container_metrics: bool,
        loot_analytics: bool,
        supply_refill: bool,
    },
    SupplyRefillPlan {
        observation: u32,
        purchase: Option<(u16, u32)>,
    },
    LootSummary {
        total: LootTotals,
        monster: String,
        monster_total: Option<LootTotals>,
    },
    FiringComparison {
        observation: u32,
        matches: bool,
    },
    TargetComparison {
        observation: u32,
        selected: Option<u32>,
        suggested: Option<u32>,
    },
    Probe {
        id: u32,
        origin: Position,
        destination: Position,
    },
    WatchTile {
        position: Position,
    },
    RouteProbe {
        id: u32,
        origin: Position,
        destination: Position,
    },
}

#[derive(Debug, PartialEq, Eq)]
pub enum SessionError {
    Oversize,
    InvalidFrame,
    Authentication,
    Closed,
    Sequence,
    Stale,
}

pub fn decode(frame: &str) -> Result<ClientFrame, SessionError> {
    if frame.len() > MAX_FRAME {
        return Err(SessionError::Oversize);
    }
    serde_json::from_str(frame).map_err(|_| SessionError::InvalidFrame)
}

pub struct Session {
    credentials: Option<([u8; 64], [u8; 64])>,
    authenticated: bool,
    path_probe: bool,
    sequence: u32,
    position: Option<Position>,
    last_creature_move: Option<(u32, Position)>,
    container_metrics: Option<ContainerMetrics>,
    loot_total: LootTotals,
    loot_by_monster: std::collections::BTreeMap<String, LootTotals>,
    pending: Option<(u32, u64)>,
    probe_result: Option<Option<u8>>,
    heal_times: [Vec<u32>; 2],
    preview: Option<Preview>,
}

impl Session {
    pub fn new(token: [u8; 64], proof: [u8; 64]) -> Self {
        Self {
            credentials: Some((token, proof)),
            authenticated: false,
            path_probe: false,
            sequence: 0,
            position: None,
            last_creature_move: None,
            container_metrics: None,
            loot_total: LootTotals::default(),
            loot_by_monster: std::collections::BTreeMap::new(),
            pending: None,
            probe_result: None,
            heal_times: Default::default(),
            preview: None,
        }
    }

    pub fn with_preview(mut self, goal: Position) -> Self {
        self.preview = Some(Preview::new(goal));
        self
    }

    pub fn take_preview_decision(&mut self) -> Option<route::Decision> {
        self.preview.as_mut()?.take_decision()
    }

    pub fn take_container_metrics(&mut self) -> Option<ContainerMetrics> {
        self.container_metrics.take()
    }

    pub fn position(&self) -> Option<Position> {
        self.position
    }

    pub fn last_creature_move(&self) -> Option<(u32, Position)> {
        self.last_creature_move
    }

    pub fn probe_result(&self) -> Option<Option<u8>> {
        self.probe_result
    }

    pub fn handle(
        &mut self,
        frame: ClientFrame,
        now_ms: u64,
    ) -> Result<Option<ServerFrame>, SessionError> {
        if !self.authenticated {
            return self.authenticate(frame);
        }

        match frame {
            ClientFrame::Hello { .. } => Err(SessionError::Sequence),
            ClientFrame::Snapshot { sequence, position } => {
                self.advance(sequence)?;
                if self.position.is_some() || position.z > 15 {
                    return Err(SessionError::InvalidFrame);
                }
                self.position = Some(position);
                if !self.path_probe {
                    return Ok(None);
                }

                if let Some(preview) = self.preview.as_mut() {
                    preview.initialize(position);
                    return Ok(preview.response(sequence, now_ms));
                }

                self.pending = Some((sequence, now_ms.saturating_add(2_000)));
                Ok(Some(ServerFrame::Probe {
                    id: sequence,
                    origin: position,
                    destination: position.adjacent(),
                }))
            }
            ClientFrame::Move { sequence, position } => {
                self.advance(sequence)?;
                let previous = self.position.ok_or(SessionError::Sequence)?;
                if position.z > 15 {
                    return Err(SessionError::InvalidFrame);
                }
                if previous != position {
                    self.pending = None;
                }
                if previous.z != position.z {
                    self.last_creature_move = None;
                }
                self.position = Some(position);
                if let Some(preview) = self.preview.as_mut().filter(|_| self.path_probe) {
                    preview.observe(route::Event::Player(position));
                    return Ok(preview.response(sequence, now_ms));
                }
                Ok(None)
            }
            ClientFrame::CreatureMove {
                sequence,
                id,
                position,
            } => {
                self.advance(sequence)?;
                let player = self.position.ok_or(SessionError::Sequence)?;
                if id == 0 || position.z > 15 {
                    return Err(SessionError::InvalidFrame);
                }
                if player.z == position.z {
                    self.last_creature_move = Some((id, position));
                }
                Ok(None)
            }
            ClientFrame::HealComparison {
                sequence,
                hp,
                mp,
                mana,
                rules,
                selected,
            } => {
                self.advance(sequence)?;
                self.position.ok_or(SessionError::Sequence)?;
                if hp > 10000
                    || mp > 10000
                    || rules.len() > 24
                    || rules.iter().any(|r| r.threshold > 100)
                    || selected.is_some_and(|i| i == 0 || i > rules.len())
                {
                    return Err(SessionError::InvalidFrame);
                }
                let suggested = healing::choose(hp, mp, mana, &rules);
                if suggested != selected {
                    println!("heal comparison {sequence}: local={selected:?} rust={suggested:?}");
                }
                Ok(None)
            }
            ClientFrame::HealDispatch {
                sequence,
                elapsed_ms,
                echo,
            } => {
                self.advance(sequence)?;
                self.position.ok_or(SessionError::Sequence)?;
                let times = &mut self.heal_times[usize::from(echo)];
                let phase = if echo { "spell echo" } else { "dispatch" };
                times.push(elapsed_ms);
                if times.len() == 32 {
                    times.sort_unstable();
                    println!(
                        "heal {phase} ms (32 samples): p50={} p95={} max={}",
                        times[15], times[30], times[31]
                    );
                    times.clear();
                }
                Ok(None)
            }
            ClientFrame::SupplyRefill { sequence, stock } => {
                self.advance(sequence)?;
                self.position.ok_or(SessionError::Sequence)?;
                if stock.len() > 48 || stock.iter().any(|&(id, _, _)| id == 0) {
                    return Err(SessionError::InvalidFrame);
                }
                let purchase = stock.into_iter().find_map(|(id, owned, desired)| {
                    let missing = desired.saturating_sub(owned).min(100);
                    (missing > 0).then_some((id, missing))
                });
                Ok(Some(ServerFrame::SupplyRefillPlan {
                    observation: sequence,
                    purchase,
                }))
            }
            ClientFrame::LootReport {
                sequence,
                monster,
                nonempty,
            } => {
                self.advance(sequence)?;
                self.position.ok_or(SessionError::Sequence)?;
                if monster.is_empty() || monster.len() > 96 || monster.chars().any(char::is_control)
                {
                    return Err(SessionError::InvalidFrame);
                }
                self.loot_total.record(nonempty);
                if self.loot_by_monster.len() < 64 || self.loot_by_monster.contains_key(&monster) {
                    self.loot_by_monster
                        .entry(monster.clone())
                        .or_default()
                        .record(nonempty);
                }
                Ok(Some(ServerFrame::LootSummary {
                    total: self.loot_total,
                    monster_total: self.loot_by_monster.get(&monster).copied(),
                    monster,
                }))
            }
            ClientFrame::ContainerMetrics { sequence, metrics } => {
                self.advance(sequence)?;
                self.position.ok_or(SessionError::Sequence)?;
                if !metrics.valid() {
                    return Err(SessionError::InvalidFrame);
                }
                self.container_metrics = Some(metrics);
                Ok(None)
            }
            ClientFrame::FiringShadow {
                sequence,
                target,
                min,
                max,
                selected,
                positions,
            } => {
                use navigation::{Candidate, Obstruction, choose_firing_position};

                self.advance(sequence)?;
                self.position.ok_or(SessionError::Sequence)?;
                if target.z > 15 || min > max || positions.len() > 32 {
                    return Err(SessionError::InvalidFrame);
                }
                let candidates: Vec<_> = positions
                    .into_iter()
                    .map(|(position, cost)| Candidate {
                        position,
                        cost,
                        obstruction: Obstruction::Clear,
                        sight: true,
                    })
                    .collect();
                Ok(Some(ServerFrame::FiringComparison {
                    observation: sequence,
                    matches: choose_firing_position(target, min..=max, &candidates)
                        == Some(selected),
                }))
            }
            ClientFrame::TargetShadow {
                sequence,
                selected,
                current,
                candidates,
            } => {
                self.advance(sequence)?;
                let player = self.position.ok_or(SessionError::Sequence)?;
                if candidates.len() > 24
                    || candidates.iter().any(|candidate| {
                        candidate.id == 0 || candidate.position.z > 15 || candidate.hp > 100
                    })
                {
                    return Err(SessionError::InvalidFrame);
                }
                Ok(Some(ServerFrame::TargetComparison {
                    observation: sequence,
                    selected,
                    suggested: navigation::choose_target(player, current, &candidates),
                }))
            }
            ClientFrame::Tile {
                sequence,
                position,
                walkable,
                ignore_creatures,
            } => {
                self.advance(sequence)?;
                let preview = self.preview.as_mut().ok_or(SessionError::Sequence)?;
                if position.z > 15 || walkable.is_some() != ignore_creatures.is_some() {
                    return Err(SessionError::InvalidFrame);
                }
                preview.tile(position, walkable.zip(ignore_creatures));
                Ok(preview.response(sequence, now_ms))
            }
            ClientFrame::RouteGoal { sequence, position } => {
                self.advance(sequence)?;
                let current = self.position.ok_or(SessionError::Sequence)?;
                if !self.path_probe || position.is_some_and(|position| position.z > 15) {
                    return Err(SessionError::InvalidFrame);
                }
                let Some(position) = position else {
                    if let Some(preview) = self.preview.as_mut() {
                        preview.clear_goal();
                    }
                    return Ok(None);
                };
                let preview = self.preview.get_or_insert_with(|| {
                    let mut preview = Preview::new(position);
                    preview.initialize(current);
                    preview
                });
                preview.observe(route::Event::Goal(position));
                Ok(preview.response(sequence, now_ms))
            }
            ClientFrame::RouteAck {
                sequence,
                id,
                directions,
            } => {
                self.advance(sequence)?;
                let preview = self.preview.as_mut().ok_or(SessionError::Stale)?;
                preview.complete(id, directions.as_deref().unwrap_or_default(), now_ms)?;
                Ok(preview.response(sequence, now_ms))
            }
            ClientFrame::Ack {
                sequence,
                id,
                path_result,
            } => {
                self.advance(sequence)?;
                let (pending_id, expires_at) = self.pending.take().ok_or(SessionError::Stale)?;
                if pending_id != id || now_ms >= expires_at {
                    return Err(SessionError::Stale);
                }
                if path_result.is_some_and(|code| code > 4) {
                    return Err(SessionError::InvalidFrame);
                }
                self.probe_result = Some(path_result);
                Ok(None)
            }
        }
    }

    fn authenticate(&mut self, frame: ClientFrame) -> Result<Option<ServerFrame>, SessionError> {
        let (token, proof) = self.credentials.take().ok_or(SessionError::Closed)?;
        let ClientFrame::Hello {
            protocol,
            token: supplied,
            bridge_version,
            path_probe,
        } = frame
        else {
            return Err(SessionError::Authentication);
        };

        if protocol != PROTOCOL
            || bridge_version != BRIDGE_VERSION
            || !bool::from(token.ct_eq(supplied.as_bytes()))
        {
            return Err(SessionError::Authentication);
        }

        self.authenticated = true;
        self.path_probe = path_probe;
        let proof = String::from_utf8(proof.to_vec()).map_err(|_| SessionError::Authentication)?;
        Ok(Some(ServerFrame::Ready {
            proof,
            protocol: PROTOCOL,
            cave_shadow: self.preview.is_none() && path_probe,
            heal_timing: true,
            target_shadow: true,
            container_metrics: true,
            loot_analytics: true,
            supply_refill: true,
        }))
    }

    fn advance(&mut self, sequence: u32) -> Result<(), SessionError> {
        if self.sequence.checked_add(1) != Some(sequence) {
            return Err(SessionError::Sequence);
        }

        self.sequence = sequence;
        Ok(())
    }
}

/// Dispatch a native observation to its domain. The OTClient owns execution.
pub fn decide(operation: &str, input: serde_json::Value) -> Option<serde_json::Value> {
    match operation {
        "self_heal" | "ally_heal" | "ally_target" | "attack" => {
            combat_runtime::decide(operation, input)
        }
        "movement_dispatch" | "movement_goal" | "movement_vote" => {
            movement_runtime::decide(operation, input)
        }
        _ => inventory_runtime::decide(operation, input),
    }
}
