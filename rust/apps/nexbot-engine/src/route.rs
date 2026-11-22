use crate::{Position, navigation::Obstruction};

const MAX_PATH_TILES: usize = 64;

pub enum Event<'a> {
    Player(Position),
    Goal(Position),
    Tile {
        position: Position,
        obstruction: Obstruction,
    },
    Path {
        generation: u64,
        tiles: &'a [Position],
    },
    Deadline {
        generation: u64,
    },
}

#[derive(Debug, PartialEq, Eq)]
pub enum Decision {
    Wait,
    Plan {
        generation: u64,
        from: Position,
        to: Position,
    },
    Step(Position),
    AwaitFloor,
    WaitCreature(Position),
    Blocked,
    Arrived,
}

#[derive(Default)]
pub struct Route {
    player: Option<Position>,
    goal: Option<Position>,
    generation: u64,
    planning: bool,
    blocked: Option<Position>,
    path: Vec<Position>,
    cursor: usize,
}

impl Route {
    pub fn on_event(&mut self, event: Event<'_>) -> Decision {
        match event {
            Event::Goal(position) if self.goal != Some(position) => {
                self.goal = Some(position);
                self.plan()
            }
            Event::Player(position) if self.player != Some(position) => {
                self.player = Some(position);
                if self.path.get(self.cursor) == Some(&position) {
                    self.cursor += 1;
                    self.next_step()
                } else {
                    self.plan()
                }
            }
            Event::Tile {
                position,
                obstruction,
            } => self.observe_tile(position, obstruction),
            Event::Path { generation, tiles } if self.planning && generation == self.generation => {
                self.planning = false;
                let Some(player) = self.player else {
                    return Decision::Wait;
                };
                if tiles.is_empty()
                    || tiles.len() > MAX_PATH_TILES
                    || tiles.last().copied() != self.goal
                    || !std::iter::once(&player)
                        .chain(tiles)
                        .zip(tiles)
                        .all(|(from, to)| from.distance(*to) == Some(1))
                {
                    return Decision::Blocked;
                }
                self.path.extend_from_slice(tiles);
                self.next_step()
            }
            Event::Deadline { generation }
                if generation == self.generation
                    && (self.planning || self.cursor < self.path.len()) =>
            {
                self.reset_path();
                Decision::Blocked
            }
            _ => Decision::Wait,
        }
    }

    fn plan(&mut self) -> Decision {
        self.reset_path();
        self.blocked = None;
        let (Some(from), Some(to)) = (self.player, self.goal) else {
            return Decision::Wait;
        };
        if from.z != to.z {
            return Decision::AwaitFloor;
        }
        if from == to {
            return Decision::Arrived;
        }
        let Some(generation) = self.generation.checked_add(1) else {
            return Decision::Blocked;
        };

        self.generation = generation;
        self.planning = true;
        Decision::Plan {
            generation,
            from,
            to,
        }
    }

    fn observe_tile(&mut self, position: Position, obstruction: Obstruction) -> Decision {
        if obstruction == Obstruction::Clear && self.blocked == Some(position) {
            return self.plan();
        }
        if !self.path[self.cursor..].contains(&position) && self.blocked != Some(position) {
            return Decision::Wait;
        }
        match obstruction {
            Obstruction::Terrain => self.plan(),
            Obstruction::Creature => {
                self.reset_path();
                self.blocked = Some(position);
                Decision::WaitCreature(position)
            }
            Obstruction::Unknown => {
                self.reset_path();
                self.blocked = Some(position);
                Decision::Blocked
            }
            Obstruction::Clear => Decision::Wait,
        }
    }

    fn reset_path(&mut self) {
        self.planning = false;
        self.path.clear();
        self.cursor = 0;
    }

    fn next_step(&self) -> Decision {
        match self.path.get(self.cursor) {
            Some(position) => Decision::Step(*position),
            None => Decision::Arrived,
        }
    }
}
