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
        position: Position,
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
        target_shadow: bool,
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
    pending: Option<(u32, u64)>,
    probe_result: Option<Option<u8>>,
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
            pending: None,
            probe_result: None,
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
                if !self.path_probe || position.z > 15 {
                    return Err(SessionError::InvalidFrame);
                }
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
            target_shadow: true,
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
