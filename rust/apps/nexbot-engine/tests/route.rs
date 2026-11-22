use nexbot_engine::{
    Position,
    navigation::Obstruction,
    route::{Decision, Event, Route},
};

fn tile(x: u16, y: u16, z: u8) -> Position {
    Position { x, y, z }
}

#[test]
fn only_replans_when_relevant_observations_change() {
    let start = tile(10, 10, 7);
    let step = tile(11, 10, 7);
    let goal = tile(12, 10, 7);
    let mut route = Route::default();
    assert_eq!(route.on_event(Event::Player(start)), Decision::Wait);
    assert_eq!(
        route.on_event(Event::Goal(goal)),
        Decision::Plan {
            generation: 1,
            from: start,
            to: goal
        }
    );
    assert_eq!(
        route.on_event(Event::Path {
            generation: 1,
            tiles: &[step, goal]
        }),
        Decision::Step(step)
    );

    for i in 0..10_000 {
        assert_eq!(
            route.on_event(Event::Tile {
                position: tile(100 + i, 5, 7),
                obstruction: Obstruction::Terrain
            }),
            Decision::Wait
        );
    }

    assert_eq!(route.on_event(Event::Player(start)), Decision::Wait);
    assert_eq!(route.on_event(Event::Player(step)), Decision::Step(goal));
    assert_eq!(route.on_event(Event::Player(goal)), Decision::Arrived);
}

#[test]
fn floor_change_deadline_and_collision_invalidate_older_paths() {
    let start = tile(10, 10, 7);
    let step = tile(11, 10, 7);
    let goal = tile(12, 10, 7);
    let upstairs = tile(10, 10, 6);
    let mut route = Route::default();
    route.on_event(Event::Player(start));
    route.on_event(Event::Goal(goal));
    route.on_event(Event::Path {
        generation: 1,
        tiles: &[step, goal],
    });

    assert_eq!(
        route.on_event(Event::Tile {
            position: step,
            obstruction: Obstruction::Creature
        }),
        Decision::WaitCreature(step)
    );
    assert_eq!(
        route.on_event(Event::Tile {
            position: step,
            obstruction: Obstruction::Clear
        }),
        Decision::Plan {
            generation: 2,
            from: start,
            to: goal
        }
    );
    assert_eq!(
        route.on_event(Event::Path {
            generation: 1,
            tiles: &[step, goal]
        }),
        Decision::Wait
    );
    assert_eq!(
        route.on_event(Event::Deadline { generation: 1 }),
        Decision::Wait
    );
    assert_eq!(
        route.on_event(Event::Deadline { generation: 2 }),
        Decision::Blocked
    );
    assert_eq!(
        route.on_event(Event::Player(upstairs)),
        Decision::AwaitFloor
    );
    assert_eq!(
        route.on_event(Event::Player(start)),
        Decision::Plan {
            generation: 3,
            from: start,
            to: goal
        }
    );
}

#[test]
fn malformed_paths_and_unexpected_movement_never_authorize_a_step() {
    let start = tile(10, 10, 7);
    let goal = tile(12, 10, 7);
    let new_start = tile(10, 11, 7);
    let first = tile(11, 11, 7);
    let mut route = Route::default();
    route.on_event(Event::Player(start));
    route.on_event(Event::Goal(goal));

    assert_eq!(
        route.on_event(Event::Path {
            generation: 1,
            tiles: &[goal]
        }),
        Decision::Blocked
    );
    assert_eq!(
        route.on_event(Event::Player(new_start)),
        Decision::Plan {
            generation: 2,
            from: new_start,
            to: goal
        }
    );
    assert_eq!(
        route.on_event(Event::Path {
            generation: 2,
            tiles: &[first, goal]
        }),
        Decision::Step(first)
    );
    assert_eq!(
        route.on_event(Event::Player(start)),
        Decision::Plan {
            generation: 3,
            from: start,
            to: goal
        }
    );
}

#[test]
fn terrain_change_replans_without_waiting_for_the_tile_to_clear() {
    let start = tile(10, 10, 7);
    let step = tile(11, 10, 7);
    let goal = tile(12, 10, 7);
    let mut route = Route::default();
    route.on_event(Event::Player(start));
    route.on_event(Event::Goal(goal));
    route.on_event(Event::Path {
        generation: 1,
        tiles: &[step, goal],
    });
    assert_eq!(
        route.on_event(Event::Tile {
            position: step,
            obstruction: Obstruction::Terrain,
        }),
        Decision::Plan {
            generation: 2,
            from: start,
            to: goal,
        }
    );
}
