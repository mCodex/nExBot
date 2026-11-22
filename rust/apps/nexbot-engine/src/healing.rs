use serde::Deserialize;

/// Rows arrive in the active profile's priority order, spells before potions.
/// The client resolves availability against its live cooldown and item state.
#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct Rule {
    pub mana_cost: u32,
    pub threshold: u8,
    pub mana_trigger: bool,
    pub above: bool,
    pub ready: bool,
}

pub fn choose(hp: u16, mp: u16, mana: u32, rules: &[Rule]) -> Option<usize> {
    if hp == 0 {
        return None;
    }
    rules
        .iter()
        .position(|rule| {
            let value = if rule.mana_trigger { mp } else { hp };
            let limit = u16::from(rule.threshold) * 100;
            rule.ready
                && rule.mana_cost <= mana
                && if rule.above {
                    value >= limit
                } else {
                    value <= limit
                }
        })
        .map(|index| index + 1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn crossing_threshold_with_sufficient_mana_picks_first_ready_rule() {
        let rules = [Rule {
            mana_cost: 100,
            threshold: 50,
            mana_trigger: false,
            above: false,
            ready: true,
        }];
        assert_eq!(choose(5001, 7000, 100, &rules), None);
        assert_eq!(choose(5000, 7000, 100, &rules), Some(1));
        assert_eq!(choose(4900, 7000, 99, &rules), None);
        assert_eq!(choose(0, 7000, 100, &rules), None);
    }
}
