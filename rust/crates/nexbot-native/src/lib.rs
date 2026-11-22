//! C ABI for the synchronous OTClient adapter. Domain policy stays in nexbot-engine.

use std::{panic::catch_unwind, slice, str};

const MAX_REQUEST_BYTES: usize = 16_384;

fn decide(operation: &[u8], input: &[u8]) -> Option<Vec<u8>> {
    let operation = str::from_utf8(operation).ok()?;
    let decision = nexbot_engine::decide_json(operation, input)?;
    serde_json::to_vec(&decision).ok()
}

/// # Safety
/// Inputs must be readable for their lengths. Output must be writable for its
/// capacity and must not overlap either input. The buffers must remain valid
/// through this call. The function retains no pointers.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nexbot_decide_v1(
    operation: *const u8,
    operation_len: usize,
    input: *const u8,
    input_len: usize,
    output: *mut u8,
    output_capacity: usize,
) -> usize {
    if operation.is_null()
        || input.is_null()
        || output.is_null()
        || operation_len > 64
        || input_len > MAX_REQUEST_BYTES
        || output_capacity > MAX_REQUEST_BYTES
    {
        return 0;
    }

    let result = catch_unwind(|| {
        // The C++ caller owns all three nonoverlapping buffers for this call.
        let operation = unsafe { slice::from_raw_parts(operation, operation_len) };
        let input = unsafe { slice::from_raw_parts(input, input_len) };
        let decision = decide(operation, input)?;
        if decision.len() > output_capacity {
            return None;
        }
        let output = unsafe { slice::from_raw_parts_mut(output, decision.len()) };
        output.copy_from_slice(&decision);
        Some(decision.len())
    });

    result.ok().flatten().unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::decide;

    #[test]
    fn preserves_v1_duplicate_keys_and_rejects_trailing_or_unknown_input() {
        let repeated =
            br#"{"safe_steps":0,"safe_steps":3,"allow_segment":true,"field_ahead":false}"#;
        assert_eq!(
            decide(b"movement_dispatch", repeated).as_deref(),
            Some(&b"3"[..])
        );
        let trailing = [repeated.as_slice(), b" {}"].concat();
        assert!(decide(b"movement_dispatch", &trailing).is_none());
        assert!(
            decide(
                b"movement_dispatch",
                br#"{"safe_steps":3,"allow_segment":true,"field_ahead":false,"extra":1}"#
            )
            .is_none()
        );
    }

    #[test]
    fn compact_pagination_matches_legacy_when_advancing_wrapping_or_finishing() {
        for (page, continuation, first, visited, expected) in [
            (0, false, true, vec![0], r#"{"page":8}"#),
            (8, false, false, vec![8], r#"{"page":0}"#),
            (0, true, true, vec![0, 8], "{}"),
            (8, false, true, vec![8, 0], "{}"),
        ] {
            let legacy = serde_json::json!({"page":page,"capacity":8,"size":12,"visited":visited});
            let compact = serde_json::json!({"page":page,"capacity":8,"size":12,"continuation_visited":continuation,"first_visited":first});
            for observation in [legacy, compact] {
                let encoded = serde_json::to_vec(&observation).unwrap();
                assert_eq!(
                    decide(b"reopen_page", &encoded).as_deref(),
                    Some(expected.as_bytes())
                );
            }
        }
    }
}
