use std::{
    fs,
    io::{self, Write},
    path::Path,
};

use serde::{Deserialize, Serialize};

#[derive(Default, Deserialize, Serialize)]
#[serde(default)]
struct TargetProfile {
    targeting: Vec<TargetRule>,
    looting: LootRules,
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct TargetRule {
    name: String,
    regex: Option<String>,
    exclude_regex: Option<String>,
    priority: Option<u32>,
    danger: Option<u32>,
    max_distance: Option<u32>,
    #[serde(default = "default_chase")]
    chase: bool,
    #[serde(default)]
    keep_distance: bool,
    keep_distance_range: Option<u32>,
    #[serde(default)]
    dont_loot: bool,
}

#[derive(Deserialize, Serialize)]
#[serde(default, rename_all = "camelCase")]
struct LootRules {
    items: Vec<LootEntry>,
    containers: Vec<LootEntry>,
    every_item: bool,
    max_danger: u32,
    min_capacity: u32,
    eat_from_corpses: bool,
}

#[derive(Deserialize, Serialize)]
struct LootEntry {
    id: u16,
}

impl Default for LootRules {
    fn default() -> Self {
        Self {
            items: Vec::new(),
            containers: Vec::new(),
            every_item: false,
            max_danger: 10,
            min_capacity: 100,
            eat_from_corpses: false,
        }
    }
}

fn default_chase() -> bool {
    true
}

pub(crate) fn inspect(path: &Path) -> io::Result<()> {
    let profile: TargetProfile = serde_json::from_slice(&fs::read(path)?)?;
    let mut output = io::stdout().lock();
    serde_json::to_writer_pretty(&mut output, &profile)?;
    writeln!(output)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_priorities_chase_and_loot_without_reordering_rules() {
        let profile: TargetProfile = serde_json::from_str(
            r#"{"targeting":[
                {"name":"Chicken","priority":10,"keepDistance":true,"dontLoot":true},
                {"name":"Bear"},{"name":"Orc*"}
            ],"looting":{"everyItem":false,"minCapacity":100,"eatFromCorpses":false}}"#,
        )
        .unwrap();
        let names: Vec<_> = profile
            .targeting
            .iter()
            .map(|rule| rule.name.as_str())
            .collect();
        assert_eq!(names, ["Chicken", "Bear", "Orc*"]);
        assert_eq!(profile.targeting[0].priority, Some(10));
        assert!(profile.targeting[0].chase);
        assert!(profile.targeting[0].keep_distance);
        assert!(profile.targeting[0].dont_loot);
        assert!(!profile.looting.every_item);
        assert_eq!(profile.looting.min_capacity, 100);
        assert!(!profile.looting.eat_from_corpses);
    }

    #[test]
    fn accepts_a_profile_without_optional_sections_or_rule_fields() {
        let profile: TargetProfile =
            serde_json::from_str(r#"{"targeting":[{"name":"Demon"}]}"#).unwrap();
        assert!(profile.targeting[0].chase);
        assert!(profile.targeting[0].regex.is_none());
        assert_eq!(profile.looting.min_capacity, 100);
    }

    #[test]
    fn preserves_explicit_loot_ids_and_rejects_wrong_field_types() {
        let rules: LootRules = serde_json::from_str(
            r#"{"items":[{"id":3031,"count":1}],"containers":[{"id":2854}],"everyItem":true}"#,
        )
        .unwrap();
        assert_eq!(rules.items[0].id, 3031);
        assert_eq!(rules.containers[0].id, 2854);
        assert!(rules.every_item);
        assert!(serde_json::from_str::<LootRules>(r#"{"items":[{"id":"3031"}]}"#).is_err());
    }
}
