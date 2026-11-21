use nexbot_engine::{
    Position,
    navigation::{Candidate, Obstruction, choose_firing_position, follow_distance},
};

fn position(x: u16, y: u16, z: u8) -> Position {
    Position { x, y, z }
}

#[test]
fn distinguishes_transient_occupants_and_unknown_tiles_from_terrain() {
    assert_eq!(Obstruction::observed(None), Obstruction::Unknown);
    assert_eq!(
        Obstruction::observed(Some((false, false))),
        Obstruction::Terrain
    );
    assert_eq!(
        Obstruction::observed(Some((false, true))),
        Obstruction::Creature
    );
    assert_eq!(
        Obstruction::observed(Some((true, true))),
        Obstruction::Clear
    );
}

#[test]
fn firing_position_respects_sight_floor_and_collision_before_cost() {
    let target = position(10, 10, 7);
    let candidate = |position, cost, obstruction, sight| Candidate {
        position,
        cost,
        obstruction,
        sight,
    };
    let candidates = [
        candidate(position(9, 10, 7), 1, Obstruction::Clear, false),
        candidate(position(8, 10, 7), 2, Obstruction::Creature, true),
        candidate(position(9, 10, 6), 3, Obstruction::Clear, true),
        candidate(position(6, 10, 7), 2, Obstruction::Clear, true),
        candidate(position(12, 10, 7), 8, Obstruction::Clear, true),
        candidate(position(10, 12, 7), 8, Obstruction::Clear, true),
        candidate(target, 1, Obstruction::Clear, true),
    ];

    assert_eq!(
        choose_firing_position(target, 1..=3, &candidates),
        Some(position(10, 12, 7))
    );
    assert_eq!(
        choose_firing_position(target, 1..=3, &candidates[..4]),
        None
    );
}

#[test]
fn follow_holds_within_one_sqm_and_requires_an_observed_floor() {
    let follower = position(10, 10, 7);
    assert_eq!(follow_distance(follower, position(11, 11, 7)), Some(0));
    assert_eq!(follow_distance(follower, position(10, 15, 7)), Some(4));
    assert_eq!(follow_distance(follower, position(10, 10, 6)), None);
}
