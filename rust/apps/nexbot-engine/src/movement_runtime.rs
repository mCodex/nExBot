use crate::Position;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

const SINGLE_STEP_THRESHOLD: u8 = 2;
const MAX_SEGMENT_STEPS: u8 = 40;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Dispatch {
    Stop,
    Step,
    Segment(u8),
}

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct DispatchObservation {
    pub safe_steps: u8,
    pub field_ahead: bool,
    pub allow_segment: bool,
}

/// Selects the dispatch size from the floor-safe path prefix observed by the client.
pub fn select_dispatch(observation: &DispatchObservation) -> Dispatch {
    match observation.safe_steps {
        0 => Dispatch::Stop,
        1..=SINGLE_STEP_THRESHOLD => Dispatch::Step,
        _ if observation.field_ahead || !observation.allow_segment => Dispatch::Step,
        count => Dispatch::Segment(count.min(MAX_SEGMENT_STEPS)),
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Goal {
    Continue,
    Reached,
    AwaitFloor,
}

pub fn goal_status(
    player: Position,
    goal: Position,
    precision: Option<u16>,
    margin: Option<(u16, u16)>,
) -> Goal {
    let Some(distance) = player.distance(goal) else {
        return Goal::AwaitFloor;
    };
    if precision.is_some_and(|limit| distance <= limit)
        || margin.is_some_and(|(min, max)| (min..=max).contains(&distance))
    {
        Goal::Reached
    } else {
        Goal::Continue
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct GoalObservation {
    player: Position,
    goal: Position,
    precision: Option<u16>,
    margin_min: Option<u16>,
    margin_max: Option<u16>,
}

const MAX_VOTERS: usize = 32;

#[derive(Clone, Copy, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Intent {
    pub position: Position,
    pub priority: u16,
    pub confidence: f64,
}

#[derive(Debug, PartialEq, Serialize)]
pub struct Vote {
    pub index: usize,
    pub confidence: f64,
}

#[derive(Clone, Copy)]
struct Group {
    index: usize,
    votes: u16,
    priority: u32,
    confidence: f64,
}

pub fn aggregate(player: Position, intents: &[Intent]) -> Option<Vote> {
    if intents.len() > MAX_VOTERS {
        return None;
    }
    let mut groups: [Option<Group>; MAX_VOTERS] = [None; MAX_VOTERS];
    for (index, intent) in intents.iter().enumerate() {
        if intent.position.z != player.z || !(0.0..=1.0).contains(&intent.confidence) {
            continue;
        }
        for occupied in &mut groups {
            match occupied {
                Some(group) => {
                    let lead = intents[group.index].position;
                    if lead
                        .distance(intent.position)
                        .is_some_and(|distance| distance <= 1)
                    {
                        group.votes += 1;
                        group.priority += u32::from(intent.priority);
                        group.confidence += intent.confidence;
                        break;
                    }
                }
                None => {
                    *occupied = Some(Group {
                        index,
                        votes: 1,
                        priority: u32::from(intent.priority),
                        confidence: intent.confidence,
                    });
                    break;
                }
            }
        }
    }

    for left in 0..groups.len() {
        let Some(group) = groups[left] else { break };
        for right in left + 1..groups.len() {
            let Some(other) = groups[right] else { break };
            let a = intents[group.index].position;
            let b = intents[other.index].position;
            let dx = i64::from(a.x) - i64::from(player.x);
            let dy = i64::from(a.y) - i64::from(player.y);
            let bx = i64::from(b.x) - i64::from(player.x);
            let by = i64::from(b.y) - i64::from(player.y);
            if dx * bx + dy * by < 0 {
                let lower = if group.priority < other.priority {
                    left
                } else {
                    right
                };
                if let Some(loser) = &mut groups[lower] {
                    loser.confidence *= 0.5;
                }
            }
        }
    }

    let mut best = None;
    let mut best_score = -1.0;
    for group in groups.into_iter().flatten() {
        let votes = f64::from(group.votes);
        let confidence = group.confidence / votes;
        let score = f64::from(group.priority) * confidence * (1.0 + (votes - 1.0) * 0.2);
        if score > best_score {
            best_score = score;
            best = Some(Vote {
                index: group.index + 1,
                confidence,
            });
        }
    }
    best
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct VoteObservation {
    player: Position,
    intents: Vec<Intent>,
}

pub fn decide(operation: &str, input: Value) -> Option<Value> {
    match operation {
        "movement_dispatch" => {
            let observation = serde_json::from_value(input).ok()?;
            Some(json!(match select_dispatch(&observation) {
                Dispatch::Stop => 0,
                Dispatch::Step => 1,
                Dispatch::Segment(steps) => steps,
            }))
        }
        "movement_goal" => {
            let observation: GoalObservation = serde_json::from_value(input).ok()?;
            let margin = observation.margin_min.zip(observation.margin_max);
            Some(json!(match goal_status(
                observation.player,
                observation.goal,
                observation.precision,
                margin
            ) {
                Goal::Continue => "continue",
                Goal::Reached => "reached",
                Goal::AwaitFloor => "await_floor",
            }))
        }
        "movement_vote" => {
            let observation: VoteObservation = serde_json::from_value(input).ok()?;
            if observation.intents.len() > MAX_VOTERS {
                return None;
            }
            Some(
                aggregate(observation.player, &observation.intents)
                    .map_or_else(|| json!({}), |vote| json!(vote)),
            )
        }
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn limits_dispatch_to_the_prefix_and_walks_one_checked_field_at_a_time() {
        let mut observation = DispatchObservation {
            safe_steps: 60,
            field_ahead: false,
            allow_segment: true,
        };
        assert_eq!(select_dispatch(&observation), Dispatch::Segment(40));
        observation.field_ahead = true;
        assert_eq!(select_dispatch(&observation), Dispatch::Step);
        observation.safe_steps = 0;
        assert_eq!(select_dispatch(&observation), Dispatch::Stop);
        observation.safe_steps = 3;
        observation.field_ahead = false;
        observation.allow_segment = false;
        assert_eq!(select_dispatch(&observation), Dispatch::Step);
    }

    #[test]
    fn validates_floor_before_precision_or_combat_margin() {
        let origin = Position { x: 10, y: 20, z: 7 };
        let goal = Position { x: 13, y: 22, z: 7 };
        assert_eq!(goal_status(origin, goal, Some(2), None), Goal::Continue);
        assert_eq!(goal_status(origin, goal, Some(3), None), Goal::Reached);
        assert_eq!(goal_status(origin, goal, None, Some((3, 5))), Goal::Reached);
        assert_eq!(
            goal_status(origin, Position { z: 8, ..goal }, Some(9), None),
            Goal::AwaitFloor
        );
    }
    #[test]
    fn groups_nearby_votes_and_discards_votes_on_other_floors() {
        let player = Position {
            x: 100,
            y: 100,
            z: 7,
        };
        let intent = |x, z, priority, confidence| Intent {
            position: Position { x, z, ..player },
            priority,
            confidence,
        };
        let intents = [
            intent(120, 8, 100, 1.0),
            intent(104, 7, 80, 0.6),
            intent(105, 7, 40, 0.8),
            intent(95, 7, 55, 1.0),
        ];
        assert_eq!(
            aggregate(player, &intents),
            Some(Vote {
                index: 2,
                confidence: 0.7
            })
        );
        assert_eq!(aggregate(player, &intents[..1]), None);
    }
}
