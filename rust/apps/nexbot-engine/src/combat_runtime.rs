use serde::Deserialize;
use serde_json::Value;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SelfHeal {
    hp: f64,
    mp: f64,
    mana: f64,
    in_pz: bool,
    rules: Vec<SelfRule>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SelfRule {
    hp: Option<f64>,
    mp: Option<f64>,
    above: bool,
    potion: bool,
    cost: f64,
    ready: bool,
}

fn self_heal(input: &SelfHeal) -> Option<usize> {
    if input.hp <= 0.0 {
        return None;
    }

    input.rules.iter().position(|rule| {
        if !rule.ready || input.mana < rule.cost {
            return false;
        }
        let matches = |value, threshold| {
            if rule.above {
                value >= threshold
            } else {
                value <= threshold
            }
        };
        let hp_matches = rule
            .hp
            .is_some_and(|threshold| matches(input.hp, threshold));
        let mp_matches = rule
            .mp
            .is_some_and(|threshold| matches(input.mp, threshold));
        if rule.potion {
            (!input.in_pz || input.hp <= 30.0) && (hp_matches || mp_matches)
        } else if rule.hp.is_some() {
            hp_matches
        } else {
            mp_matches
        }
    })
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct AllyHeal {
    self_hp: f64,
    self_mp: f64,
    min_hp: f64,
    min_mp: f64,
    mana: f64,
    hp: f64,
    distance: f64,
    can_shoot: bool,
    friends_needing_heal: usize,
    rules: Vec<AllyRule>,
}

#[derive(Deserialize)]
#[serde(rename_all = "snake_case")]
enum AllyAction {
    Spell,
    AreaSpell,
    Rune,
    ManaPotion,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct AllyRule {
    action: AllyAction,
    threshold: f64,
    range: f64,
    cost: f64,
    ready: bool,
    min_friends: usize,
}

fn ally_heal(input: &AllyHeal) -> Option<usize> {
    if input.self_hp < input.min_hp.max(50.0) || input.self_mp < input.min_mp || input.hp <= 0.0 {
        return None;
    }

    input.rules.iter().position(|rule| {
        if !rule.ready || input.mana < rule.cost || input.distance > rule.range {
            return false;
        }
        match rule.action {
            AllyAction::Spell => input.can_shoot && input.hp <= rule.threshold,
            AllyAction::AreaSpell => {
                input.hp < rule.threshold && input.friends_needing_heal >= rule.min_friends
            }
            AllyAction::Rune => input.can_shoot && input.hp < rule.threshold,
            AllyAction::ManaPotion => true,
        }
    })
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct AllyTargets {
    self_hp: f64,
    candidates: Vec<AllyCandidate>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct AllyCandidate {
    hp: f64,
    threshold: f64,
    distance: f64,
    can_shoot: bool,
}

fn ally_target(input: &AllyTargets) -> Option<usize> {
    if input.self_hp < 50.0 {
        return None;
    }

    let mut best = None;
    let mut best_score = 0.0;
    for (index, candidate) in input.candidates.iter().enumerate() {
        if candidate.hp <= 0.0
            || candidate.hp >= candidate.threshold
            || candidate.distance > 7.0
            || !candidate.can_shoot
        {
            continue;
        }
        let score = 100.0 - candidate.hp - candidate.distance * 2.0;
        if score > best_score {
            best = Some(index);
            best_score = score;
        }
    }
    best
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct AttackRule {
    observed: f64,
    required: f64,
    mana: f64,
    required_mana: f64,
    target_hp: f64,
    min_hp: f64,
    max_hp: f64,
    distance: f64,
    max_distance: Option<f64>,
    at_least: bool,
    players_nearby: bool,
    protect_players: bool,
}

fn attack(rule: &AttackRule) -> bool {
    if rule.mana < rule.required_mana
        || !(rule.min_hp..=rule.max_hp).contains(&rule.target_hp)
        || rule.max_distance.is_some_and(|limit| rule.distance > limit)
        || (rule.protect_players && rule.players_nearby)
    {
        return false;
    }

    if rule.at_least {
        rule.observed >= rule.required
    } else {
        rule.observed == rule.required
    }
}

pub fn decide(operation: &str, input: Value) -> Option<Value> {
    match operation {
        "self_heal" => {
            let input = serde_json::from_value(input).ok()?;
            Some(Value::from(self_heal(&input).map_or(0, |index| index + 1)))
        }
        "ally_heal" => {
            let input = serde_json::from_value(input).ok()?;
            Some(Value::from(ally_heal(&input).map_or(0, |index| index + 1)))
        }
        "ally_target" => {
            let input = serde_json::from_value(input).ok()?;
            Some(Value::from(
                ally_target(&input).map_or(0, |index| index + 1),
            ))
        }
        "attack" => {
            let rule = serde_json::from_value(input).ok()?;
            Some(Value::from(attack(&rule)))
        }
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::decide;

    #[test]
    fn self_heal_respects_exact_crossings_and_profile_order() {
        let mut input = json!({
            "hp": 50.001, "mp": 30, "mana": 100, "in_pz": false,
            "rules": [
                {"hp": 50, "mp": null, "above": false, "potion": false, "cost": 100, "ready": true},
                {"hp": null, "mp": 30, "above": false, "potion": true, "cost": 0, "ready": true}
            ]
        });

        assert_eq!(decide("self_heal", input.clone()), Some(json!(2)));
        input["hp"] = json!(50);
        assert_eq!(decide("self_heal", input.clone()), Some(json!(1)));
        input["mana"] = json!(99);
        input["in_pz"] = json!(true);
        assert_eq!(decide("self_heal", input), Some(json!(0)));
    }

    #[test]
    fn ally_heal_protects_self_and_skips_blocked_targeted_actions() {
        let mut input = json!({
            "self_hp": 49, "self_mp": 100, "min_hp": 20, "min_mp": 50,
            "mana": 150, "hp": 30, "distance": 1, "can_shoot": true,
            "friends_needing_heal": 2,
            "rules": [
                {"action": "spell", "threshold": 30, "range": 7, "cost": 100, "ready": true, "min_friends": 0},
                {"action": "area_spell", "threshold": 80, "range": 7, "cost": 150, "ready": true, "min_friends": 2}
            ]
        });

        assert_eq!(decide("ally_heal", input.clone()), Some(json!(0)));
        input["self_hp"] = json!(100);
        assert_eq!(decide("ally_heal", input.clone()), Some(json!(1)));
        input["can_shoot"] = json!(false);
        assert_eq!(decide("ally_heal", input.clone()), Some(json!(2)));
        input["hp"] = json!(0);
        assert_eq!(decide("ally_heal", input), Some(json!(0)));
    }

    #[test]
    fn ally_target_prefers_urgency_with_stable_order_for_ties() {
        let input = json!({
            "self_hp": 80,
            "candidates": [
                {"hp": 30, "threshold": 80, "distance": 4, "can_shoot": true},
                {"hp": 34, "threshold": 80, "distance": 2, "can_shoot": true},
                {"hp": 10, "threshold": 80, "distance": 1, "can_shoot": false},
                {"hp": 0, "threshold": 80, "distance": 0, "can_shoot": true}
            ]
        });

        assert_eq!(decide("ally_target", input), Some(json!(1)));
    }

    #[test]
    fn attack_checks_exact_counts_and_safety() {
        let mut input = json!({"observed": 4, "required": 3, "at_least": false,
            "players_nearby": true, "protect_players": true, "mana": 75, "required_mana": 50,
            "target_hp": 70, "min_hp": 0, "max_hp": 100, "distance": 4, "max_distance": 4});

        assert_eq!(decide("attack", input.clone()), Some(json!(false)));
        input["at_least"] = json!(true);
        assert_eq!(decide("attack", input.clone()), Some(json!(false)));
        input["protect_players"] = json!(false);
        assert_eq!(decide("attack", input.clone()), Some(json!(true)));
        input["distance"] = json!(5);
        assert_eq!(decide("attack", input), Some(json!(false)));
    }
}
