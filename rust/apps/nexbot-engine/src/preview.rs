use crate::{
    Position, ServerFrame, SessionError,
    navigation::Obstruction,
    route::{Decision, Event, Route},
};

pub(crate) struct Preview {
    goal: Position,
    route: Route,
    decision: Option<Decision>,
    pending: Option<Query>,
    watch: Option<Position>,
}

struct Query {
    id: u32,
    origin: Position,
    generation: u64,
    expires_at: u64,
}

impl Preview {
    pub(crate) fn new(goal: Position) -> Self {
        Self {
            goal,
            route: Route::default(),
            decision: None,
            pending: None,
            watch: None,
        }
    }

    pub(crate) fn clear_goal(&mut self) {
        self.route.clear_goal();
        self.decision = None;
        self.watch = None;
    }

    pub(crate) fn observe(&mut self, event: Event<'_>) {
        let decision = self.route.on_event(event);
        if decision != Decision::Wait {
            self.decision = Some(decision);
        }
    }

    pub(crate) fn initialize(&mut self, position: Position) {
        self.observe(Event::Player(position));
        self.observe(Event::Goal(self.goal));
    }

    pub(crate) fn take_decision(&mut self) -> Option<Decision> {
        match self.decision {
            Some(Decision::Plan { .. }) => None,
            _ => self.decision.take(),
        }
    }

    pub(crate) fn tile(&mut self, position: Position, walkability: Option<(bool, bool)>) {
        if self.watch == Some(position) {
            self.observe(Event::Tile {
                position,
                obstruction: Obstruction::observed(walkability),
            });
        }
    }

    pub(crate) fn response(&mut self, id: u32, now_ms: u64) -> Option<ServerFrame> {
        if let Some(Decision::Step(position)) = self.decision
            && self.watch != Some(position)
        {
            self.watch = Some(position);
            return Some(ServerFrame::WatchTile { position });
        }
        self.request(id, now_ms)
    }

    fn request(&mut self, id: u32, now_ms: u64) -> Option<ServerFrame> {
        if self.pending.is_some() {
            return None;
        }
        let Some(Decision::Plan {
            generation,
            from,
            to,
        }) = self.decision
        else {
            return None;
        };
        if from.distance(to).is_none_or(|distance| distance > 32) {
            self.observe(Event::Deadline { generation });
            return None;
        }

        self.decision = None;
        self.watch = None;
        self.pending = Some(Query {
            id,
            origin: from,
            generation,
            expires_at: now_ms.saturating_add(2_000),
        });
        Some(ServerFrame::RouteProbe {
            id,
            origin: from,
            destination: to,
        })
    }

    pub(crate) fn complete(
        &mut self,
        id: u32,
        directions: &[u8],
        now_ms: u64,
    ) -> Result<(), SessionError> {
        let query = self.pending.take().ok_or(SessionError::Stale)?;
        if id != query.id {
            return Err(SessionError::Stale);
        }
        if now_ms >= query.expires_at {
            self.observe(Event::Deadline {
                generation: query.generation,
            });
            return Ok(());
        }
        if directions.len() > 64 {
            return Err(SessionError::InvalidFrame);
        }
        let mut tiles = [query.origin; 64];
        let mut position = query.origin;
        for (tile, direction) in tiles.iter_mut().zip(directions) {
            position = offset(position, *direction).ok_or(SessionError::InvalidFrame)?;
            *tile = position;
        }

        self.observe(Event::Path {
            generation: query.generation,
            tiles: &tiles[..directions.len()],
        });
        Ok(())
    }
}

fn offset(position: Position, direction: u8) -> Option<Position> {
    let deltas = [
        (0, -1),
        (1, 0),
        (0, 1),
        (-1, 0),
        (1, -1),
        (1, 1),
        (-1, 1),
        (-1, -1),
    ];
    let (dx, dy) = *deltas.get(usize::from(direction))?;
    Some(Position {
        x: position.x.checked_add_signed(dx)?,
        y: position.y.checked_add_signed(dy)?,
        ..position
    })
}
