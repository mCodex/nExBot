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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
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

#[derive(Clone, Copy, Debug, PartialEq, Eq, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TargetCandidate {
    pub id: u32,
    pub position: Position,
    pub priority: i32, // Lua priority in hundredths
    pub hp: u8,
    pub cost: u16,
    pub sight: bool,
}

pub fn choose_target(
    player: Position,
    current: Option<u32>,
    candidates: &[TargetCandidate],
) -> Option<u32> {
    let eligible = |candidate: &&TargetCandidate| {
        candidate.priority > 0 && player.distance(candidate.position).is_some()
    };
    let best = candidates.iter().filter(eligible).max_by_key(|candidate| {
        (
            candidate.priority,
            candidate.sight,
            std::cmp::Reverse(candidate.cost),
            std::cmp::Reverse(candidate.id),
        )
    })?;

    if let Some(active) = candidates
        .iter()
        .filter(eligible)
        .find(|candidate| Some(candidate.id) == current)
    {
        let threshold = match active.hp {
            0..=14 => 75,
            15..=29 => 40,
            30..=49 => 25,
            50..=69 => 15,
            _ => 0,
        };
        if best.priority.saturating_sub(active.priority) < threshold * 100 {
            return Some(active.id);
        }
    }
    Some(best.id)
}
