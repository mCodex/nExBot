use nexbot_engine::{ClientFrame, Position, ServerFrame, Session, SessionError, decode};

fn position(x: u16, z: u8) -> Position {
    Position { x, y: 50, z }
}

fn session() -> Session {
    Session::new([b'a'; 64], [b'b'; 64])
}

fn hello(token: char) -> ClientFrame {
    ClientFrame::Hello {
        protocol: 1,
        token: token.to_string().repeat(64),
        bridge_version: String::from("5.0.0-alpha.1"),
        path_probe: true,
    }
}

#[test]
fn validates_wire_frames() {
    assert_eq!(decode(&" ".repeat(4_097)), Err(SessionError::Oversize));
    assert_eq!(decode("{"), Err(SessionError::InvalidFrame));
    assert_eq!(
        decode(r#"{"type":"move","sequence":2,"position":{"x":1,"y":2,"z":3,"extra":1}}"#),
        Err(SessionError::InvalidFrame)
    );
}

#[test]
fn authentication_happens_before_events_and_is_single_use() {
    let mut state = session();
    assert_eq!(
        state.handle(hello('x'), 0),
        Err(SessionError::Authentication)
    );
    assert_eq!(state.handle(hello('a'), 0), Err(SessionError::Closed));

    let mut state = session();
    assert!(matches!(
        state.handle(hello('a'), 0),
        Ok(Some(ServerFrame::Ready { .. }))
    ));
    assert_eq!(state.handle(hello('a'), 1), Err(SessionError::Sequence));
}

#[test]
fn snapshot_probes_adjacent_tile_and_accepts_correlated_response() {
    let mut state = session();
    state.handle(hello('a'), 0).unwrap();
    assert_eq!(
        state.handle(
            ClientFrame::Snapshot {
                sequence: 1,
                position: position(10, 7)
            },
            1
        ),
        Ok(Some(ServerFrame::Probe {
            id: 1,
            origin: position(10, 7),
            destination: position(11, 7)
        }))
    );
    assert_eq!(
        state.handle(
            ClientFrame::Ack {
                sequence: 2,
                id: 1,
                path_result: Some(0)
            },
            2
        ),
        Ok(None)
    );
    assert_eq!(
        state.handle(
            ClientFrame::Move {
                sequence: 3,
                position: position(11, 7)
            },
            3
        ),
        Ok(None)
    );
    assert_eq!(state.position(), Some(position(11, 7)));
    assert_eq!(state.probe_result(), Some(Some(0)));
}

#[test]
fn stale_ack_cannot_cross_generation_or_deadline() {
    let mut state = session();
    state.handle(hello('a'), 0).unwrap();
    state
        .handle(
            ClientFrame::Snapshot {
                sequence: 1,
                position: position(10, 7),
            },
            1,
        )
        .unwrap();
    state
        .handle(
            ClientFrame::Move {
                sequence: 2,
                position: position(10, 6),
            },
            2,
        )
        .unwrap();
    assert_eq!(
        state.handle(
            ClientFrame::Ack {
                sequence: 3,
                id: 1,
                path_result: None
            },
            3
        ),
        Err(SessionError::Stale)
    );

    let mut state = session();
    state.handle(hello('a'), 0).unwrap();
    state
        .handle(
            ClientFrame::Snapshot {
                sequence: 1,
                position: position(10, 7),
            },
            1,
        )
        .unwrap();
    assert_eq!(
        state.handle(
            ClientFrame::Ack {
                sequence: 2,
                id: 1,
                path_result: None
            },
            2_001
        ),
        Err(SessionError::Stale)
    );
}

#[test]
fn creature_motion_keeps_only_the_latest_observation_and_clears_on_floor_change() {
    let mut state = session();
    state.handle(hello('a'), 0).unwrap();
    state
        .handle(
            ClientFrame::Snapshot {
                sequence: 1,
                position: position(10, 7),
            },
            1,
        )
        .unwrap();
    let frame =
        r#"{"type":"creature_move","sequence":2,"id":4194305,"position":{"x":13,"y":50,"z":7}}"#;
    assert_eq!(state.handle(decode(frame).unwrap(), 2), Ok(None));
    assert_eq!(state.last_creature_move(), Some((4194305, position(13, 7))));

    state
        .handle(
            ClientFrame::Move {
                sequence: 3,
                position: position(10, 6),
            },
            3,
        )
        .unwrap();
    assert_eq!(state.last_creature_move(), None);
    let frame =
        r#"{"type":"creature_move","sequence":4,"id":4194306,"position":{"x":13,"y":50,"z":7}}"#;
    assert_eq!(state.handle(decode(frame).unwrap(), 4), Ok(None));
    assert_eq!(state.last_creature_move(), None);
}

#[test]
fn rejects_wrong_protocol_version_order_and_position() {
    let mut state = session();
    let mut frame = hello('a');
    if let ClientFrame::Hello { protocol, .. } = &mut frame {
        *protocol = 2;
    }
    assert_eq!(state.handle(frame, 0), Err(SessionError::Authentication));

    let mut state = session();
    let mut frame = hello('a');
    if let ClientFrame::Hello { bridge_version, .. } = &mut frame {
        *bridge_version = "4.0.4".to_owned();
    }
    assert_eq!(state.handle(frame, 0), Err(SessionError::Authentication));

    let snapshot = |sequence, z| ClientFrame::Snapshot {
        sequence,
        position: position(10, z),
    };
    let mut state = session();
    assert_eq!(
        state.handle(snapshot(1, 7), 0),
        Err(SessionError::Authentication)
    );

    let mut state = session();
    let mut frame = hello('a');
    if let ClientFrame::Hello { path_probe, .. } = &mut frame {
        *path_probe = false;
    }
    state.handle(frame, 0).unwrap();

    assert_eq!(state.handle(snapshot(2, 7), 0), Err(SessionError::Sequence));
    assert_eq!(
        state.handle(snapshot(1, 16), 0),
        Err(SessionError::InvalidFrame)
    );
    assert_eq!(state.handle(snapshot(2, 7), 0), Ok(None));
    assert_eq!(
        state.handle(snapshot(3, 7), 0),
        Err(SessionError::InvalidFrame)
    );
    assert_eq!(
        state.handle(
            ClientFrame::Move {
                sequence: 4,
                position: position(10, 16)
            },
            0
        ),
        Err(SessionError::InvalidFrame)
    );
    assert_eq!(
        state.handle(
            ClientFrame::CreatureMove {
                sequence: 5,
                id: 0,
                position: position(20, 7)
            },
            0
        ),
        Err(SessionError::InvalidFrame)
    );
    assert_eq!(
        state.handle(
            ClientFrame::CreatureMove {
                sequence: 6,
                id: 1,
                position: position(20, 16)
            },
            0
        ),
        Err(SessionError::InvalidFrame)
    );
}

#[test]
fn wrong_id_or_native_code_cannot_qualify_and_duplicate_motion_is_not_a_floor_change() {
    for (id, path_result, error) in [
        (3, Some(0), SessionError::Stale),
        (1, Some(5), SessionError::InvalidFrame),
    ] {
        let mut state = session();
        state.handle(hello('a'), 0).unwrap();
        let edge = position(u16::MAX, 7);
        let reply = state
            .handle(
                ClientFrame::Snapshot {
                    sequence: 1,
                    position: edge,
                },
                0,
            )
            .unwrap();
        assert_eq!(
            reply,
            Some(ServerFrame::Probe {
                id: 1,
                origin: edge,
                destination: position(u16::MAX - 1, 7)
            })
        );

        state
            .handle(
                ClientFrame::Move {
                    sequence: 2,
                    position: edge,
                },
                0,
            )
            .unwrap();
        assert_eq!(
            state.handle(
                ClientFrame::Ack {
                    sequence: 3,
                    id,
                    path_result
                },
                0
            ),
            Err(error)
        );
        assert_eq!(state.probe_result(), None);
    }
}

#[test]
fn preview_uses_native_path_and_replans_only_after_deviation() {
    let mut state = session().with_preview(position(12, 7));
    state.handle(hello('a'), 0).unwrap();
    assert_eq!(
        state.handle(
            ClientFrame::Snapshot {
                sequence: 1,
                position: position(10, 7)
            },
            1
        ),
        Ok(Some(ServerFrame::RouteProbe {
            id: 1,
            origin: position(10, 7),
            destination: position(12, 7)
        }))
    );
    let ack = r#"{"type":"route_ack","sequence":2,"id":1,"directions":[1,1]}"#;
    assert_eq!(
        state.handle(decode(ack).unwrap(), 2),
        Ok(Some(ServerFrame::WatchTile {
            position: position(11, 7)
        }))
    );
    assert_eq!(
        state.take_preview_decision(),
        Some(nexbot_engine::route::Decision::Step(position(11, 7)))
    );
    assert_eq!(
        state.handle(
            ClientFrame::Move {
                sequence: 3,
                position: position(11, 7)
            },
            3
        ),
        Ok(Some(ServerFrame::WatchTile {
            position: position(12, 7)
        }))
    );
    assert_eq!(
        state.take_preview_decision(),
        Some(nexbot_engine::route::Decision::Step(position(12, 7)))
    );
    assert_eq!(
        state.handle(
            ClientFrame::Move {
                sequence: 4,
                position: position(9, 7)
            },
            4
        ),
        Ok(Some(ServerFrame::RouteProbe {
            id: 4,
            origin: position(9, 7),
            destination: position(12, 7)
        }))
    );
}

#[test]
fn preview_watches_the_next_tile_and_replans_after_a_temporary_blocker_clears() {
    use nexbot_engine::route::Decision;
    let mut state = session().with_preview(position(12, 7));
    state.handle(hello('a'), 0).unwrap();
    state
        .handle(
            ClientFrame::Snapshot {
                sequence: 1,
                position: position(10, 7),
            },
            1,
        )
        .unwrap();
    let ack = r#"{"type":"route_ack","sequence":2,"id":1,"directions":[1,1]}"#;
    assert_eq!(
        state.handle(decode(ack).unwrap(), 2),
        Ok(Some(ServerFrame::WatchTile {
            position: position(11, 7)
        }))
    );
    assert_eq!(
        state.take_preview_decision(),
        Some(Decision::Step(position(11, 7)))
    );

    let blocked = r#"{"type":"tile","sequence":3,"position":{"x":11,"y":50,"z":7},"walkable":false,"ignore_creatures":true}"#;
    assert_eq!(state.handle(decode(blocked).unwrap(), 3), Ok(None));
    assert_eq!(
        state.take_preview_decision(),
        Some(Decision::WaitCreature(position(11, 7)))
    );
    let clear = r#"{"type":"tile","sequence":4,"position":{"x":11,"y":50,"z":7},"walkable":true,"ignore_creatures":true}"#;
    assert_eq!(
        state.handle(decode(clear).unwrap(), 4),
        Ok(Some(ServerFrame::RouteProbe {
            id: 4,
            origin: position(10, 7),
            destination: position(12, 7)
        }))
    );
}

#[test]
fn live_route_goal_reuses_the_authenticated_native_preview() {
    let mut state = session();
    assert!(matches!(
        state.handle(hello('a'), 0),
        Ok(Some(ServerFrame::Ready {
            cave_shadow: true,
            ..
        }))
    ));
    state
        .handle(
            ClientFrame::Snapshot {
                sequence: 1,
                position: position(10, 7),
            },
            1,
        )
        .unwrap();
    state
        .handle(
            ClientFrame::Ack {
                sequence: 2,
                id: 1,
                path_result: Some(0),
            },
            2,
        )
        .unwrap();
    assert_eq!(
        state.handle(
            ClientFrame::RouteGoal {
                sequence: 3,
                position: Some(position(12, 7))
            },
            3
        ),
        Ok(Some(ServerFrame::RouteProbe {
            id: 3,
            origin: position(10, 7),
            destination: position(12, 7),
        }))
    );
    assert_eq!(
        state.handle(
            ClientFrame::RouteGoal {
                sequence: 4,
                position: Some(position(12, 7))
            },
            4
        ),
        Ok(None)
    );
    assert_eq!(
        state.handle(
            ClientFrame::RouteAck {
                sequence: 5,
                id: 3,
                directions: Some(vec![1, 1])
            },
            5
        ),
        Ok(Some(ServerFrame::WatchTile {
            position: position(11, 7)
        }))
    );
    assert_eq!(
        state.handle(
            ClientFrame::RouteGoal {
                sequence: 6,
                position: Some(position(12, 6))
            },
            6
        ),
        Ok(None)
    );
    assert_eq!(
        state.take_preview_decision(),
        Some(nexbot_engine::route::Decision::AwaitFloor)
    );
}

#[test]
fn container_metrics_require_a_snapshot_and_consistent_ack_counts() {
    let mut state = session();
    assert!(matches!(
        state.handle(hello('a'), 0),
        Ok(Some(ServerFrame::Ready {
            container_metrics: true,
            ..
        }))
    ));
    let observation = |sequence, samples| ClientFrame::ContainerMetrics {
        sequence,
        metrics: nexbot_engine::ContainerMetrics {
            elapsed_ms: 2400,
            requests: 3,
            timeouts: 1,
            samples,
            ack_ms: 45,
            max_ack_ms: 45,
        },
    };
    assert!(matches!(
        state.handle(observation(1, 1), 1),
        Err(SessionError::Sequence)
    ));
    state
        .handle(
            ClientFrame::Snapshot {
                sequence: 2,
                position: position(10, 7),
            },
            1,
        )
        .unwrap();
    assert!(matches!(state.handle(observation(3, 1), 2), Ok(None)));
    assert_eq!(state.take_container_metrics().unwrap().ack_ms, 45);
    assert!(state.take_container_metrics().is_none());
    assert!(matches!(
        state.handle(observation(4, 3), 3),
        Err(SessionError::InvalidFrame)
    ));
}

#[test]
fn cancelling_a_live_waypoint_ignores_its_in_flight_path() {
    let mut state = session();
    for (sequence, json) in [
        (
            0,
            format!(
                r#"{{"type":"hello","protocol":1,"token":"{}","bridge_version":"5.0.0-alpha.1","path_probe":true}}"#,
                "a".repeat(64)
            ),
        ),
        (
            1,
            r#"{"type":"snapshot","sequence":1,"position":{"x":10,"y":50,"z":7}}"#.into(),
        ),
        (
            2,
            r#"{"type":"ack","sequence":2,"id":1,"path_result":0}"#.into(),
        ),
        (
            3,
            r#"{"type":"route_goal","sequence":3,"position":{"x":12,"y":50,"z":7}}"#.into(),
        ),
        (4, r#"{"type":"route_goal","sequence":4}"#.into()),
        (
            5,
            r#"{"type":"route_ack","sequence":5,"id":3,"directions":[1,1]}"#.into(),
        ),
    ] {
        let reply = state.handle(decode(&json).unwrap(), sequence).unwrap();
        if sequence >= 4 {
            assert_eq!(reply, None);
        }
    }
    assert_eq!(state.take_preview_decision(), None);
}

#[test]
fn compares_firing_positions_from_native_reachability_without_issuing_an_action() {
    let mut state = session();
    state.handle(hello('a'), 0).unwrap();
    state
        .handle(
            ClientFrame::Snapshot {
                sequence: 1,
                position: position(10, 7),
            },
            1,
        )
        .unwrap();
    let frame = decode(r#"{"type":"firing_shadow","sequence":2,"target":{"x":13,"y":50,"z":7},"min":2,"max":4,"selected":{"x":10,"y":50,"z":7},"positions":[[{"x":10,"y":50,"z":7},250],[{"x":9,"y":50,"z":7},300],[{"x":12,"y":50,"z":7},50]]}"#).unwrap();
    assert_eq!(
        state.handle(frame, 2),
        Ok(Some(ServerFrame::FiringComparison {
            observation: 2,
            matches: true
        }))
    );
}

#[test]
fn aggregates_loot_by_monster_and_caps_the_number_of_groups() {
    use nexbot_engine::LootTotals;
    let mut state = session();
    state.handle(hello('a'), 0).unwrap();
    state
        .handle(
            ClientFrame::Snapshot {
                sequence: 1,
                position: position(10, 7),
            },
            1,
        )
        .unwrap();
    for index in 0..65 {
        let name = format!("monster {index}");
        let totals = state
            .handle(
                ClientFrame::LootReport {
                    sequence: 2 + index,
                    monster: name.clone(),
                    nonempty: true,
                },
                2,
            )
            .unwrap()
            .unwrap();
        assert_eq!(
            totals,
            ServerFrame::LootSummary {
                total: LootTotals {
                    reports: index + 1,
                    nonempty: index + 1
                },
                monster: name,
                monster_total: (index < 64).then_some(LootTotals {
                    reports: 1,
                    nonempty: 1
                }),
            }
        );
    }
    assert_eq!(
        state.handle(
            ClientFrame::LootReport {
                sequence: 67,
                monster: "monster 0".into(),
                nonempty: false
            },
            3
        ),
        Ok(Some(ServerFrame::LootSummary {
            total: LootTotals {
                reports: 66,
                nonempty: 65
            },
            monster: "monster 0".into(),
            monster_total: Some(LootTotals {
                reports: 2,
                nonempty: 1
            }),
        }))
    );
}

#[test]
fn supply_refill_skips_complete_stock_and_caps_the_next_purchase() {
    let mut state = session();
    state.handle(hello('a'), 0).unwrap();
    state
        .handle(
            ClientFrame::Snapshot {
                sequence: 1,
                position: position(10, 7),
            },
            1,
        )
        .unwrap();
    assert_eq!(
        state.handle(
            ClientFrame::SupplyRefill {
                sequence: 2,
                stock: vec![(200, 50, 30), (201, 10, 200), (202, 0, 50)],
            },
            2,
        ),
        Ok(Some(ServerFrame::SupplyRefillPlan {
            observation: 2,
            purchase: Some((201, 100)),
        }))
    );
}
