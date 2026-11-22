use std::{
    collections::BTreeMap,
    fs,
    io::{self, Write},
    path::Path,
};

use nexbot_engine::Position;
use serde::Serialize;

#[derive(Default, Serialize)]
struct RouteReport<'a> {
    waypoints: usize,
    actions: BTreeMap<&'a str, usize>,
    floor_transitions: Vec<FloorTransition>,
    malformed: Vec<MalformedRow>,
}

#[derive(Serialize)]
struct FloorTransition {
    from_line: usize,
    to_line: usize,
    from: Position,
    to: Position,
}

#[derive(Serialize)]
struct MalformedRow {
    line: usize,
    reason: &'static str,
}

pub(crate) fn inspect(path: &Path) -> io::Result<()> {
    let contents = fs::read_to_string(path)?;
    let report = parse(&contents);
    let mut output = io::stdout().lock();
    serde_json::to_writer_pretty(&mut output, &report)?;
    writeln!(output)?;
    if !report.malformed.is_empty() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "route contains malformed rows",
        ));
    }
    Ok(())
}

fn parse(source: &str) -> RouteReport<'_> {
    let mut report = RouteReport::default();
    let mut previous: Option<(usize, Position)> = None;
    let mut multiline = None;
    for (index, row) in source.trim_start_matches('\u{feff}').lines().enumerate() {
        let line = index + 1;
        if multiline.is_some() {
            if row.contains("]]") {
                multiline = None;
            }
            continue;
        }
        if row.trim().is_empty() {
            continue;
        }

        let Some((action, value)) = row
            .split_once(':')
            .filter(|(action, _)| !action.trim().is_empty() && action.len() <= 20)
        else {
            report.malformed.push(MalformedRow {
                line,
                reason: "expected action:value",
            });
            continue;
        };
        *report.actions.entry(action).or_default() += 1;

        if let Some(body) = value.strip_prefix("[[")
            && !body.contains("]]")
        {
            multiline = Some(line);
        }
        if action != "goto" {
            continue;
        }
        let Some(position) = parse_position(value) else {
            report.malformed.push(MalformedRow {
                line,
                reason: "expected goto:x,y,z[,precision]",
            });
            previous = None;
            continue;
        };

        report.waypoints += 1;
        if let Some((from_line, from)) = previous.filter(|(_, from)| from.z != position.z) {
            report.floor_transitions.push(FloorTransition {
                from_line,
                to_line: line,
                from,
                to: position,
            });
        }
        previous = Some((line, position));
    }
    if let Some(line) = multiline {
        report.malformed.push(MalformedRow {
            line,
            reason: "unterminated multiline action",
        });
    }
    report
}

fn parse_position(value: &str) -> Option<Position> {
    let mut fields = value.split(',').map(str::trim);
    let x = fields.next()?.parse().ok()?;
    let y = fields.next()?.parse().ok()?;
    let z = fields.next()?.parse().ok()?;
    if z > 15
        || fields.next().is_some_and(|precision| {
            precision
                .parse::<u8>()
                .map_or(true, |precision| precision > 9)
        })
        || fields.next().is_some()
    {
        return None;
    }
    Some(Position { x, y, z })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bundled_route_keeps_waypoint_order_and_reports_floor_change() {
        let report = parse(include_str!("../../../../cavebot_configs/Demon_Alburn.cfg"));
        assert!(report.malformed.is_empty());
        assert_eq!(report.waypoints, 49);
        assert_eq!(report.floor_transitions.len(), 1);
        let change = &report.floor_transitions[0];
        assert_eq!((change.from_line, change.to_line), (49, 50));
        assert_eq!((change.from.z, change.to.z), (6, 7));
    }

    #[test]
    fn multiline_custom_actions_are_opaque_and_bad_rows_report_line_numbers() {
        let report = parse(concat!(
            "\u{feff}goto:1,2,7,0\r\n",
            "custom_action:[[\r\ngoto:22,33,4\r\n]]\r\n",
            "goto:1,2,99\r\n",
            "goto: 1 , 2 , 8\r\n",
            "missing_separator\r\n",
            "custom_action:[[\r\n",
        ));
        assert_eq!(report.waypoints, 2);
        assert_eq!(report.actions["custom_action"], 2);
        assert!(report.floor_transitions.is_empty());
        assert_eq!(
            report
                .malformed
                .iter()
                .map(|row| row.line)
                .collect::<Vec<_>>(),
            [5, 7, 8]
        );
    }
}
