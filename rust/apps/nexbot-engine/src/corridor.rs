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

fn reconstruct_path(cells: &[u8], stride: usize, start: usize, goal: usize) -> Vec<u8> {
    let stride = stride as isize;
    let backstep = [
        stride,
        -1,
        -stride,
        1,
        stride - 1,
        -stride - 1,
        1 - stride,
        stride + 1,
    ];
    let mut route = Vec::new();
    let mut index = goal;
    while index != start {
        let direction = cells[index];
        route.push(direction);
        index = index
            .checked_add_signed(backstep[usize::from(direction)])
            .expect("visited cells point to an interior predecessor");
    }
    route.reverse();
    route
}

fn shortest_path(tiles: &[u8], width: usize, start: usize, goal: usize) -> Vec<u8> {
    if start == goal || tiles[goal] != b'1' {
        return Vec::new();
    }
    let height = tiles.len() / width;
    let stride = width + 2;
    // A wall border keeps every neighbor of a queued cell inside the buffer.
    let mut cells = vec![b'0'; stride * (height + 2)];
    for (y, row) in tiles.chunks_exact(width).enumerate() {
        let first = (y + 1) * stride + 1;
        cells[first..first + width].copy_from_slice(row);
    }
    let padded = |index: usize| (index / width + 1) * stride + index % width + 1;
    let start = padded(start);
    let goal = padded(goal);
    if cells[start] == b'1' {
        cells[start] = 8;
    }
    let mut queue = Vec::with_capacity(tiles.len());
    queue.push(start);
    let mut head = 0;
    while head < queue.len() {
        let current = queue[head];
        head += 1;
        let north = current - stride;
        let south = current + stride;
        let east = current + 1;
        let west = current - 1;
        let walk_north = cells[north] != b'0';
        let walk_south = cells[south] != b'0';
        let walk_east = cells[east] != b'0';
        let walk_west = cells[west] != b'0';
        // OTClient direction order breaks ties between equally short paths.
        let neighbors = [
            (north, true),
            (east, true),
            (south, true),
            (west, true),
            (north + 1, walk_north && walk_east),
            (south + 1, walk_south && walk_east),
            (south - 1, walk_south && walk_west),
            (north - 1, walk_north && walk_west),
        ];
        for (direction, (next, clear)) in neighbors.into_iter().enumerate() {
            if !clear || cells[next] != b'1' {
                continue;
            }
            cells[next] = direction as u8;
            if next == goal {
                return reconstruct_path(&cells, stride, start, goal);
            }
            queue.push(next);
        }
    }
    Vec::new()
}

pub(crate) fn decide<'de>(input: impl serde::Deserializer<'de>) -> Option<serde_json::Value> {
    let map: Map = Deserialize::deserialize(input).ok()?;
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

    #[test]
    fn leaves_an_occupied_start_and_never_wraps_across_row_edges() {
        assert_eq!(shortest_path(b"011", 1, 0, 2), [2, 2]);
        assert_eq!(shortest_path(b"111111", 3, 2, 3), [3, 6]);
        assert!(shortest_path(b"001100", 3, 2, 3).is_empty());
    }
}
