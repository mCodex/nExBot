use std::{
    env, fs,
    io::{self, Read, Write},
    net::{Ipv4Addr, TcpListener, TcpStream},
    path::Path,
    process::ExitCode,
    thread,
    time::{Duration, Instant},
};

use nexbot_engine::{MAX_FRAME, Position, ServerFrame, Session, decode, route::Decision};
use tungstenite::{
    Message, accept_hdr_with_config,
    handshake::server::{ErrorResponse, Request, Response},
    protocol::WebSocketConfig,
};

fn main() -> ExitCode {
    let arguments: Vec<_> = env::args_os().skip(1).collect();
    let result = match arguments.as_slice() {
        [flag] if flag == "--version" => {
            println!("nexbot-engine {}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        [command, path] if command == "diagnose" => diagnose(Path::new(path), None),
        [command, path, x, y, z] if command == "preview" => {
            match (parse_number(x), parse_number(y), parse_number(z)) {
                (Some(x), Some(y), Some(z @ 0..=15)) => {
                    diagnose(Path::new(path), Some(Position { x, y, z }))
                }
                _ => Err(io::Error::other("invalid preview coordinates")),
            }
        }
        _ => Err(io::Error::other(
            "usage: nexbot-engine --version | diagnose <rust-session> | preview <rust-session> X Y Z",
        )),
    };

    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("nExBot: {error}");
            ExitCode::FAILURE
        }
    }
}

fn parse_number<T: std::str::FromStr>(value: &std::ffi::OsStr) -> Option<T> {
    value.to_str()?.parse().ok()
}

struct Rendezvous<'a>(&'a Path);

impl Drop for Rendezvous<'_> {
    fn drop(&mut self) {
        let _ = fs::remove_file(self.0);
    }
}

fn publish<'a>(
    path: &'a Path,
    port: u16,
    token: &[u8],
    proof: &[u8],
) -> io::Result<Rendezvous<'a>> {
    let mut options = fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }

    let mut file = options.open(path)?;
    let guard = Rendezvous(path);
    writeln!(file, "{port}")?;
    file.write_all(token)?;
    file.write_all(b"\n")?;
    file.write_all(proof)?;
    file.write_all(b"\n")?;
    file.sync_all()?;
    Ok(guard)
}

fn credential() -> io::Result<[u8; 64]> {
    let mut random = [0; 32];
    getrandom::fill(&mut random).map_err(|_| io::Error::other("secure random unavailable"))?;
    let mut hex = [0; 64];
    for (byte, digits) in random.iter().zip(hex.as_chunks_mut::<2>().0) {
        let alphabet = b"0123456789abcdef";
        digits[0] = alphabet[(byte >> 4) as usize];
        digits[1] = alphabet[(byte & 15) as usize];
    }
    Ok(hex)
}

fn connection(listener: &TcpListener) -> io::Result<TcpStream> {
    listener.set_nonblocking(true)?;
    let deadline = Instant::now() + Duration::from_secs(90);
    loop {
        match listener.accept() {
            Ok((stream, _)) => return Ok(stream),
            Err(error)
                if error.kind() == io::ErrorKind::WouldBlock && Instant::now() < deadline =>
            {
                thread::sleep(Duration::from_millis(25));
            }
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                return Err(io::Error::new(
                    io::ErrorKind::TimedOut,
                    "waiting for the Lua bridge",
                ));
            }
            Err(error) => return Err(error),
        }
    }
}

struct TimedSocket {
    stream: TcpStream,
    deadline: Instant,
}

impl TimedSocket {
    fn remaining(&self) -> io::Result<Duration> {
        let remaining = self.deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            return Err(io::Error::new(io::ErrorKind::TimedOut, "IPC deadline"));
        }
        Ok(remaining)
    }
}

impl Read for TimedSocket {
    fn read(&mut self, bytes: &mut [u8]) -> io::Result<usize> {
        self.stream.set_read_timeout(Some(self.remaining()?))?;
        self.stream.read(bytes)
    }
}

impl Write for TimedSocket {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.stream.set_write_timeout(Some(self.remaining()?))?;
        self.stream.write(bytes)
    }

    fn flush(&mut self) -> io::Result<()> {
        self.stream.flush()
    }
}

fn diagnose(path: &Path, goal: Option<Position>) -> io::Result<()> {
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0))?;
    let address = listener.local_addr()?;
    let token = credential()?;
    let proof = credential()?;
    let mut rendezvous = Some(publish(path, address.port(), &token, &proof)?);
    println!("waiting on {address}");

    let stream = connection(&listener)?;
    stream.set_nonblocking(false)?;
    stream.set_nodelay(true)?;
    let stream = TimedSocket {
        stream,
        deadline: Instant::now() + Duration::from_secs(5),
    };
    let config = WebSocketConfig::default()
        .read_buffer_size(MAX_FRAME)
        .write_buffer_size(0)
        .max_write_buffer_size(2 * MAX_FRAME)
        .max_message_size(Some(MAX_FRAME))
        .max_frame_size(Some(MAX_FRAME));

    let host = address.to_string();
    let native_origin = format!("ws://{address}");
    #[allow(clippy::result_large_err)] // Tungstenite owns the callback signature.
    let handshake = |request: &Request, response: Response| {
        let mut origins = request.headers().get_all("origin").iter();
        if request
            .uri()
            .path_and_query()
            .is_some_and(|path| path.as_str() == "/")
            && request
                .headers()
                .get("host")
                .is_some_and(|value| value.as_bytes() == host.as_bytes())
            && origins
                .next()
                .is_none_or(|value| value.as_bytes() == native_origin.as_bytes())
            && origins.next().is_none()
        {
            Ok(response)
        } else {
            let mut rejected = ErrorResponse::new(None);
            *rejected.status_mut() = tungstenite::http::StatusCode::FORBIDDEN;
            Err(rejected)
        }
    };

    let mut socket = accept_hdr_with_config(stream, handshake, Some(config))
        .map_err(|_| io::Error::other("WebSocket handshake failed"))?;
    let mut session = Session::new(token, proof);
    if let Some(goal) = goal {
        session = session.with_preview(goal);
    }
    let started = Instant::now();
    let mut probe_reported = false;

    loop {
        let frame = socket
            .read()
            .map_err(|_| io::Error::other("IPC frame or connection failed"))?;
        let now_ms = started.elapsed().as_millis().try_into().unwrap_or(u64::MAX);
        match frame {
            Message::Text(text) => {
                let reply = decode(&text)
                    .and_then(|frame| session.handle(frame, now_ms))
                    .map_err(|error| io::Error::other(format!("rejected IPC frame ({error:?})")))?;

                socket.get_mut().deadline = Instant::now() + Duration::from_secs(20);
                if let Some(reply) = reply {
                    if matches!(reply, ServerFrame::Ready { .. }) {
                        drop(rendezvous.take());
                        println!("authenticated Lua bridge");
                    }
                    let text = serde_json::to_string(&reply).map_err(io::Error::other)?;
                    socket.send(Message::text(text)).map_err(io::Error::other)?;
                }
                if !probe_reported && let Some(result) = session.probe_result() {
                    match result {
                        Some(code) => {
                            println!("native path query confirmed ({code})");
                            println!("nexbot-ipc-health-v1");
                            io::stdout().flush()?;
                        }
                        None => println!("native path query rejected by bridge"),
                    }
                    probe_reported = true;
                }
                if let Some(decision) = session.take_preview_decision() {
                    match decision {
                        Decision::Step(tile) => {
                            println!("preview next tile {},{},{}", tile.x, tile.y, tile.z)
                        }
                        Decision::Arrived => println!("preview destination reached"),
                        Decision::Blocked => println!("preview route unavailable"),
                        Decision::AwaitFloor => println!("preview waiting for floor"),
                        Decision::Wait | Decision::Plan { .. } => {}
                    }
                }
            }
            Message::Ping(_) | Message::Pong(_) => {
                if rendezvous.is_none() {
                    socket.get_mut().deadline = Instant::now() + Duration::from_secs(20);
                }
                socket.flush().map_err(io::Error::other)?;
            }
            Message::Close(_) => return Ok(()),
            _ => return Err(io::Error::other("unsupported IPC frame")),
        }
    }
}
