use std::{fs, io, path::Path};

use serde_json::Value;

pub fn audit(directory: &Path) -> io::Result<()> {
    let mut found = false;
    let mut issues = Vec::new();
    for (file, root, selected) in [
        ("AttackBot.json", "AttackBot", "currentBotProfile"),
        ("HealBot.json", "healbot", "currentHealBotProfile"),
    ] {
        let data = match fs::read(directory.join(file)) {
            Ok(data) => data,
            Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
            Err(error) => return Err(error),
        };
        found = true;
        match serde_json::from_slice(&data) {
            Ok(document) => inspect(&document, root, selected, &mut issues),
            Err(error) => issues.push(format!("{file}: invalid JSON ({error})")),
        }
    }
    if !found {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            "profile directory has neither AttackBot.json nor HealBot.json",
        ));
    }
    for issue in &issues {
        println!("{issue}");
    }
    if issues.is_empty() {
        println!("Combat profile audit passed");
        Ok(())
    } else {
        Err(io::Error::other(format!(
            "combat profile audit found {} issues",
            issues.len()
        )))
    }
}

fn inspect(document: &Value, root: &str, selected: &str, issues: &mut Vec<String>) {
    let Some(profiles) = document.get(root).and_then(Value::as_array) else {
        issues.push(format!("{root}: expected a profile list"));
        return;
    };
    let selected_index = document.get(selected).map_or(Some(1), Value::as_u64);
    if !selected_index.is_some_and(|index| (1..=profiles.len() as u64).contains(&index)) {
        issues.push(format!(
            "{selected}: select an existing profile (1–{})",
            profiles.len()
        ));
    }
    let tables: &[&str] = if root == "AttackBot" {
        &["attackTable"]
    } else {
        &["spellTable", "itemTable"]
    };
    for (index, profile) in profiles.iter().enumerate() {
        let prefix = format!("{root}[{}]", index + 1);
        if !profile.is_object() {
            issues.push(format!("{prefix}: expected an object"));
            continue;
        }
        for table in tables {
            let value = &profile[*table];
            if value.as_object().is_some_and(|object| object.is_empty()) {
                continue;
            }
            let Some(rules) = value.as_array() else {
                issues.push(format!("{prefix}.{table}: expected a rule list"));
                continue;
            };
            for (index, rule) in rules.iter().enumerate() {
                let path = format!("{prefix}.{table}[{}]", index + 1);
                if !rule.is_object() {
                    issues.push(format!("{path}: expected a rule object"));
                    continue;
                }
                let enabled = match rule.get("enabled") {
                    None => *table != "attackTable",
                    Some(Value::Bool(enabled)) => *enabled,
                    _ => {
                        issues.push(format!("{path}.enabled: expected true or false"));
                        continue;
                    }
                };
                if !enabled {
                    continue;
                }
                for error in rule_errors(table, rule) {
                    issues.push(format!("{path}.{error}"));
                }
            }
        }
    }
}

fn rule_errors(table: &str, rule: &Value) -> Vec<&'static str> {
    let mut issues = Vec::new();
    let has_spell = rule["spell"].as_str().is_some_and(|text| {
        !text.trim().is_empty() && !text.trim().eq_ignore_ascii_case("spell name")
    });
    if table == "attackTable" {
        match rule["category"].as_u64() {
            Some(1 | 4 | 5) if !has_spell => issues.push("spell: enter a spell formula"),
            Some(2 | 3)
                if !rule["itemId"]
                    .as_u64()
                    .is_some_and(|id| id > 100 && id <= u16::MAX.into()) =>
            {
                issues.push("itemId: enter a valid rune ID");
            }
            Some(1..=5) => {}
            _ => issues.push("category: choose a supported attack category (1–5)"),
        }
        for (field, error) in [
            ("count", "count: enter a nonnegative creature count"),
            ("pattern", "pattern: choose an attack pattern"),
            (
                "patternCategory",
                "patternCategory: choose a pattern category",
            ),
        ] {
            if !rule[field]
                .as_u64()
                .is_some_and(|value| value > 0 || field == "count")
            {
                issues.push(error);
            }
        }
        for (field, error) in [
            ("mana", "mana: enter a percentage between 0 and 100"),
            ("minHp", "minHp: enter a percentage between 0 and 100"),
            ("maxHp", "maxHp: enter a percentage between 0 and 100"),
        ] {
            if !rule[field]
                .as_f64()
                .is_some_and(|value| (0.0..=100.0).contains(&value))
            {
                issues.push(error);
            }
        }
        if let (Some(min), Some(max)) = (rule["minHp"].as_f64(), rule["maxHp"].as_f64())
            && min > max
        {
            issues.push("minHp: set the minimum at or below maxHp");
        }
    } else {
        if table == "spellTable" && !has_spell {
            issues.push("spell: enter a spell formula");
        }
        if table == "itemTable"
            && !rule["item"]
                .as_u64()
                .is_some_and(|id| id > 0 && id <= u16::MAX.into())
        {
            issues.push("item: enter a valid potion ID");
        }
        let origin = rule["origin"].as_str();
        if !matches!(origin, Some("HP" | "HP%" | "MP" | "MP%")) {
            issues.push("origin: choose HP, HP%, MP or MP%");
        }
        if rule
            .get("sign")
            .is_some_and(|value| value.as_str() != Some("<"))
        {
            issues.push("sign: choose Below (<), the condition supported by the healing engine");
        }
        if let Some(value) = rule.get("value")
            && !value.as_f64().is_some_and(|value| {
                value >= 0.0 && (!matches!(origin, Some("HP%" | "MP%")) || value <= 100.0)
            })
        {
            issues.push("value: enter a nonnegative threshold, up to 100 for percentages");
        }
    }
    issues
}

#[cfg(test)]
mod tests {
    use super::inspect;
    use serde_json::json;

    #[test]
    fn audits_enabled_rules_and_accepts_empty_legacy_tables() {
        let document = json!({"healbot": [{"spellTable": [
            {"enabled": false, "spell": ""},
            {"spell": "exura", "origin": "HP%", "sign": ">", "value": 110}
        ], "itemTable": {}}], "currentHealBotProfile": 2});
        let mut issues = Vec::new();
        inspect(&document, "healbot", "currentHealBotProfile", &mut issues);
        assert_eq!(issues.len(), 3);
        assert!(issues[0].starts_with("currentHealBotProfile:"));
        assert!(issues[1].starts_with("healbot[1].spellTable[2].sign:"));
        assert!(issues[2].starts_with("healbot[1].spellTable[2].value:"));
    }

    #[test]
    fn reports_a_rune_without_an_item_and_an_inverted_hp_range() {
        let document = json!({"AttackBot": [{"attackTable": [
            {"enabled": true, "category": 3, "itemId": 0, "minHp": 80, "maxHp": 40, "mana": 0, "count": 1, "pattern": 1, "patternCategory": 1}
        ]}]});
        let mut issues = Vec::new();
        inspect(&document, "AttackBot", "currentBotProfile", &mut issues);
        assert_eq!(issues.len(), 2);
        assert!(issues[0].starts_with("AttackBot[1].attackTable[1].itemId:"));
        assert!(issues[1].starts_with("AttackBot[1].attackTable[1].minHp:"));
    }
}
