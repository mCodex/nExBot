//! Decisions over snapshots collected by the OTClient inventory and NPC adapters.

use std::collections::HashSet;

use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum EquipmentChange {
    Unequip,
    Equip,
}

#[derive(Clone, Copy, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EquipmentSlot {
    pub change: EquipmentChange,
    pub needs_change: bool,
    pub available: bool,
}

#[derive(Debug, PartialEq, Eq, Serialize)]
pub struct EquipmentDecision {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub index: Option<usize>,
    pub missing: bool,
}

pub fn equipment(slots: &[EquipmentSlot], safe_to_unequip: bool) -> EquipmentDecision {
    let mut missing = false;
    for change in [EquipmentChange::Unequip, EquipmentChange::Equip] {
        for (index, slot) in slots.iter().enumerate() {
            if slot.change != change || !slot.needs_change {
                continue;
            }
            let ready = match change {
                EquipmentChange::Unequip => safe_to_unequip,
                EquipmentChange::Equip => slot.available,
            };
            if ready {
                return EquipmentDecision {
                    index: Some(index + 1),
                    missing,
                };
            }
            missing = true;
        }
    }
    EquipmentDecision {
        index: None,
        missing,
    }
}

#[derive(Clone, Copy, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DepositItem {
    pub id: u32,
    pub stackable: bool,
    pub configured_index: Option<u16>,
}

#[derive(Debug, PartialEq, Eq, Serialize)]
pub struct DepositDecision {
    pub item: usize,
    pub destination_index: u16,
}

pub fn deposit(items: &[DepositItem], loot: &[u32]) -> Option<DepositDecision> {
    let loot: HashSet<_> = loot.iter().copied().collect();
    let (index, item) = items
        .iter()
        .enumerate()
        .find(|(_, item)| loot.contains(&item.id))?;
    Some(DepositDecision {
        item: index + 1,
        destination_index: item.configured_index.unwrap_or(u16::from(item.stackable)),
    })
}

pub fn next_reopen_page(page: u32, capacity: u32, size: u32, visited: &[u32]) -> Option<u32> {
    following_page(page, capacity, size).filter(|next| !visited.contains(next))
}

fn following_page(page: u32, capacity: u32, size: u32) -> Option<u32> {
    if capacity == 0 || size == 0 || page >= size {
        return None;
    }
    let next_page = page
        .checked_add(capacity)
        .filter(|next| *next < size)
        .unwrap_or(0);
    Some(next_page)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
enum ReopenQueue {
    Retry,
    Priority,
    Visible,
    Pages,
    Empty,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ReopenQueues {
    retry: bool,
    priority: bool,
    visible: bool,
    pages: bool,
}

impl ReopenQueues {
    fn next(&self) -> ReopenQueue {
        [
            (self.retry, ReopenQueue::Retry),
            (self.priority, ReopenQueue::Priority),
            (self.visible, ReopenQueue::Visible),
            (self.pages, ReopenQueue::Pages),
        ]
        .into_iter()
        .find_map(|(has_work, queue)| has_work.then_some(queue))
        .unwrap_or(ReopenQueue::Empty)
    }
}

/// Delay-only planning for legacy conversations without typed acknowledgements.
pub fn conversation(step_count: usize, interval_ms: u32) -> Option<Vec<u32>> {
    if step_count > 32 {
        return None;
    }
    (0..step_count)
        .map(|step| u32::try_from(step).ok()?.checked_mul(interval_ms))
        .collect()
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct EquipmentRequest {
    slots: Vec<EquipmentSlot>,
    safe_to_unequip: bool,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct DepositRequest {
    items: Vec<DepositItem>,
    loot: Vec<u32>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct PageRequest {
    page: u32,
    capacity: u32,
    size: u32,
    visited: Option<Vec<u32>>,
    continuation_visited: Option<bool>,
    first_visited: Option<bool>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ConversationRequest {
    count: usize,
    interval_ms: u32,
}

pub fn decide<'de>(
    operation: &str,
    input: impl serde::Deserializer<'de>,
) -> Option<serde_json::Value> {
    use serde_json::json;

    match operation {
        "equipment" => {
            let request: EquipmentRequest = Deserialize::deserialize(input).ok()?;
            if request.slots.len() > 9 {
                return None;
            }
            serde_json::to_value(equipment(&request.slots, request.safe_to_unequip)).ok()
        }
        "deposit" => {
            let request: DepositRequest = Deserialize::deserialize(input).ok()?;
            if request.items.len() > 256 || request.loot.len() > 512 {
                return None;
            }
            let decision = deposit(&request.items, &request.loot);
            Some(decision.map_or_else(|| json!({}), |plan| json!({"plan": plan})))
        }
        "reopen_job" => {
            let queues: ReopenQueues = Deserialize::deserialize(input).ok()?;
            serde_json::to_value(queues.next()).ok()
        }
        "reopen_page" => {
            let request: PageRequest = Deserialize::deserialize(input).ok()?;
            let page = match (
                request.visited,
                request.continuation_visited,
                request.first_visited,
            ) {
                (None, Some(continuation), Some(first)) => {
                    following_page(request.page, request.capacity, request.size)
                        .filter(|next| if *next == 0 { !first } else { !continuation })
                }
                (Some(visited), None, None) if visited.len() <= 256 => {
                    next_reopen_page(request.page, request.capacity, request.size, &visited)
                }
                _ => return None,
            };
            Some(page.map_or_else(|| json!({}), |page| json!({"page": page})))
        }
        "npc_conversation" => {
            let request: ConversationRequest = Deserialize::deserialize(input).ok()?;
            Some(json!({ "delays": conversation(request.count, request.interval_ms)? }))
        }
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn equipment_unequips_first_and_respects_live_danger() {
        let slots = [
            EquipmentSlot {
                change: EquipmentChange::Equip,
                needs_change: true,
                available: true,
            },
            EquipmentSlot {
                change: EquipmentChange::Unequip,
                needs_change: true,
                available: true,
            },
        ];
        assert_eq!(
            equipment(&slots, true),
            EquipmentDecision {
                index: Some(2),
                missing: false
            }
        );
        assert_eq!(
            equipment(&slots, false),
            EquipmentDecision {
                index: Some(1),
                missing: true
            }
        );
    }

    #[test]
    fn depot_selects_first_configured_loot_and_honors_explicit_destination() {
        let items = [
            DepositItem {
                id: 10,
                stackable: true,
                configured_index: None,
            },
            DepositItem {
                id: 20,
                stackable: true,
                configured_index: Some(0),
            },
        ];
        assert_eq!(
            deposit(&items, &[20]),
            Some(DepositDecision {
                item: 2,
                destination_index: 0
            })
        );
        assert_eq!(deposit(&items, &[30]), None);
    }

    #[test]
    fn reopen_drains_visible_work_before_changing_the_page() {
        let input = serde_json::json!({
            "retry": false, "priority": false, "visible": true, "pages": true,
        });
        assert_eq!(
            decide("reopen_job", input),
            Some(serde_json::json!("visible"))
        );
    }

    #[test]
    fn reopen_visits_pages_once_when_starting_in_the_middle() {
        assert_eq!(next_reopen_page(20, 10, 25, &[20]), Some(0));
        assert_eq!(next_reopen_page(0, 10, 25, &[20, 0]), Some(10));
        assert_eq!(next_reopen_page(10, 10, 25, &[20, 0, 10]), None);
    }

    #[test]
    fn conversation_preserves_spacing_and_rejects_overflow() {
        assert_eq!(conversation(3, 700), Some(vec![0, 700, 1400]));
        assert_eq!(conversation(3, u32::MAX), None);
    }
}
