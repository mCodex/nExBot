use std::ops::RangeInclusive;

use crate::Position;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Obstruction {
    Clear,
    Creature,
    Terrain,
    Unknown,
}

impl Obstruction {
    /// Native isWalkable(false) and isWalkable(true) taken in the same observation.
    pub fn observed(walkability: Option<(bool, bool)>) -> Self {
        match walkability {
            Some((true, true)) => Self::Clear,
            Some((false, true)) => Self::Creature,
            Some((false, false)) => Self::Terrain,
            None | Some((true, false)) => Self::Unknown,
        }
    }
}

#[derive(Clone, Copy, Debug)]
pub struct Candidate {
    pub position: Position,
    pub cost: u32,
    pub obstruction: Obstruction,
    pub sight: bool,
}

pub fn choose_firing_position(
    target: Position,
    range: RangeInclusive<u16>,
    candidates: &[Candidate],
) -> Option<Position> {
    candidates
        .iter()
        .filter(|candidate| {
            candidate.obstruction == Obstruction::Clear
                && candidate.sight
                && target
                    .distance(candidate.position)
                    .is_some_and(|distance| range.contains(&distance))
        })
        .min_by_key(|candidate| (candidate.cost, candidate.position.x, candidate.position.y))
        .map(|candidate| candidate.position)
}

pub fn follow_distance(follower: Position, leader: Position) -> Option<u16> {
    follower
        .distance(leader)
        .map(|distance| distance.saturating_sub(1))
}
