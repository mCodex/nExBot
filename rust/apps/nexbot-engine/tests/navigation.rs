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

#[test]
fn target_shadow_respects_floor_sight_path_cost_and_a_nearly_finished_target() {
    use nexbot_engine::navigation::{TargetCandidate, choose_target};

    let player = position(10, 10, 7);
    let candidate = |id, z, priority, hp, cost, sight| TargetCandidate {
        id,
        position: position(11, 11, z),
        priority,
        hp,
        cost,
        sight,
    };
    let candidates = [
        candidate(1, 7, 10000, 90, 3, true),
        candidate(2, 7, 10000, 90, 1, false),
        candidate(3, 7, 10000, 90, 4, true),
        candidate(4, 6, 20000, 90, 1, true),
        candidate(5, 7, 9000, 12, 2, true),
    ];
    assert_eq!(choose_target(player, None, &candidates), Some(1));
    assert_eq!(choose_target(player, Some(5), &candidates), Some(5));
    assert_eq!(choose_target(player, Some(4), &candidates), Some(1));
}
