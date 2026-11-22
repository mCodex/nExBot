use std::collections::VecDeque;

use serde::Deserialize;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Map {
    width: usize,
    height: usize,
    start: usize,
    goal: usize,
    tiles: String,
}

// OTClient direction IDs, cardinal directions first for stable ties.
const DIRECTIONS: [(isize, isize); 8] = [
    (0, -1),
    (1, 0),
    (0, 1),
    (-1, 0),
    (1, -1),
    (1, 1),
    (-1, 1),
    (-1, -1),
];

fn shortest_path(tiles: &[u8], width: usize, start: usize, goal: usize) -> Vec<u8> {
    if tiles[goal] != b'1' {
        return Vec::new();
    }
    let height = tiles.len() / width;
    let cell = |x: isize, y: isize| {
        let (x, y) = (usize::try_from(x).ok()?, usize::try_from(y).ok()?);
        (x < width && y < height).then_some(y * width + x)
    };
    const UNVISITED: u8 = u8::MAX;
    let mut previous = vec![UNVISITED; tiles.len()];
    let mut queue = VecDeque::with_capacity(tiles.len());
    queue.push_back(start);
    previous[start] = 8;

    while let Some(current) = queue.pop_front() {
        if current == goal {
            let mut route = Vec::new();
            let mut index = current;
            while index != start {
                let direction = previous[index];
                route.push(direction);
                let (dx, dy) = DIRECTIONS[usize::from(direction)];
                index = index
                    .checked_add_signed(-dy * width as isize - dx)
                    .expect("route predecessor is inside the grid");
            }
            route.reverse();
            return route;
        }
        let (x, y) = ((current % width) as isize, (current / width) as isize);
        for (direction, (dx, dy)) in DIRECTIONS.iter().copied().enumerate() {
            let Some(next) = cell(x + dx, y + dy) else {
                continue;
            };
            if tiles[next] != b'1' || previous[next] != UNVISITED {
                continue;
            }
            if dx != 0
                && dy != 0
                && (tiles[cell(x + dx, y).expect("diagonal inside grid")] != b'1'
                    || tiles[cell(x, y + dy).expect("diagonal inside grid")] != b'1')
            {
                continue;
            }
            previous[next] = direction as u8;
            queue.push_back(next);
        }
    }
    Vec::new()
}

pub(crate) fn decide(input: serde_json::Value) -> Option<serde_json::Value> {
    let map: Map = serde_json::from_value(input).ok()?;
    if !(1..=33).contains(&map.width)
        || !(1..=33).contains(&map.height)
        || map.tiles.len() != map.width * map.height
        || map.start >= map.tiles.len()
        || map.goal >= map.tiles.len()
        || !map.tiles.bytes().all(|tile| matches!(tile, b'0' | b'1'))
    {
        return None;
    }
    serde_json::to_value(shortest_path(
        map.tiles.as_bytes(),
        map.width,
        map.start,
        map.goal,
    ))
    .ok()
}

#[cfg(test)]
mod tests {
    use super::shortest_path;

    #[test]
    fn goes_around_wall_using_the_corridor() {
        assert_eq!(shortest_path(b"101101111", 3, 0, 2), [2, 2, 1, 1, 0, 0]);
    }

    #[test]
    fn refuses_to_cut_a_blocked_diagonal() {
        assert!(shortest_path(b"1001", 2, 0, 3).is_empty());
    }
}
