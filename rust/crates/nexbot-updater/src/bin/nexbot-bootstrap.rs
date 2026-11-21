#![forbid(unsafe_code)]

use std::error::Error;
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Read};
use std::path::Path;
use std::process::{Command, ExitCode, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use ed25519_dalek::VerifyingKey;
use nexbot_updater::{
    Channel, InstallOutcome, ReleaseContext, ReleaseTransport, RollbackOutcome, TrustAnchor,
    UpdateStore,
};
use semver::Version;
use serde::Deserialize;
use uuid::Uuid;

const HEALTH_SIGNAL: &str = "nexbot-ipc-health-v1";
const HEALTH_DEADLINE: Duration = Duration::from_secs(60);

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Settings {
    service_url: String,
    check_path: String,
    signed_objects_prefix: String,
    channel: Channel,
    baseline_engine_version: Version,
    bridge_version: Version,
    protocol_version: u16,
    rollout_id: Uuid,
    trusted_keys: Vec<ConfiguredKey>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ConfiguredKey {
    id: String,
    public_key_hex: String,
    revoked: bool,
}

fn main() -> ExitCode {
    if let Err(error) = run() {
        eprintln!("nExBot bootstrap: {error}");
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}

fn run() -> Result<(), Box<dyn Error>> {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    let (command, store_path, settings_path, health_path) = match args.as_slice() {
        [version] if version == "--version" => {
            println!("nexbot-bootstrap {}", env!("CARGO_PKG_VERSION"));
            return Ok(());
        }
        [command, store, settings] if matches!(command.to_str(), Some("check" | "status" | "rollback" | "active-path")) => {
            (command, store, settings, None)
        }
        [command, store, settings, health] if command == "update" => {
            (command, store, settings, Some(Path::new(health)))
        }
        _ => return Err(
            "usage: nexbot-bootstrap --version | check|status|rollback|active-path STORE SETTINGS | update STORE SETTINGS HEALTH_RENDEZVOUS".into()
        ),
    };

    let settings = read_settings(Path::new(settings_path))?;
    let store = UpdateStore::open(Path::new(store_path), settings.channel)?;

    if command == "status" {
        println!("{}", serde_json::to_string(&store.status()?)?);
        return Ok(());
    }
    if command == "active-path" {
        if let Some(path) = store.active_executable()? {
            println!("{}", path.display());
        }
        return Ok(());
    }
    if command == "rollback" {
        match store.rollback()? {
            RollbackOutcome::RestoredPrevious => println!("previous release restored"),
            RollbackOutcome::RestoredBaseline => println!("packaged baseline selected"),
            RollbackOutcome::Unavailable => println!("no installed update to undo"),
        }
        return Ok(());
    }

    let status = store.status()?;
    let context = ReleaseContext {
        channel: settings.channel,
        target: env!("NEXBOT_BUILD_TARGET"),
        engine: status.active.unwrap_or(settings.baseline_engine_version),
        bridge: settings.bridge_version,
        protocol: settings.protocol_version,
        rollout_id: settings.rollout_id,
        now: SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs(),
    };
    let anchors = settings
        .trusted_keys
        .iter()
        .map(|entry| -> Result<_, Box<dyn Error>> {
            let mut bytes = [0; 32];
            hex::decode_to_slice(&entry.public_key_hex, &mut bytes)?;
            Ok(TrustAnchor {
                id: &entry.id,
                key: VerifyingKey::from_bytes(&bytes)?,
                revoked: entry.revoked,
            })
        })
        .collect::<Result<Vec<_>, _>>()?;
    if anchors.is_empty() || anchors.iter().all(|anchor| anchor.revoked) {
        return Err("no trusted release key is configured".into());
    }

    let service = ReleaseTransport::new(
        &settings.service_url,
        &settings.check_path,
        &settings.signed_objects_prefix,
    )?;
    let Some(update) = service.check(&context, &anchors)? else {
        println!("no compatible update");
        return Ok(());
    };
    if status
        .highest_accepted
        .is_some_and(|version| &version >= update.version())
    {
        println!("release is at or below the update floor");
        return Ok(());
    }

    match health_path {
        Some(path) => {
            validate_rendezvous(path)?;
            match update.install(&store, |candidate| check_health(candidate, path))? {
                InstallOutcome::Activated => println!("update activated"),
                InstallOutcome::Rejected => {
                    return Err("candidate failed its IPC health check".into());
                }
            }
        }
        None => println!("update {} available", update.version()),
    }

    Ok(())
}

fn read_settings(path: &Path) -> Result<Settings, Box<dyn Error>> {
    let mut bytes = Vec::new();
    File::open(path)?.take(8193).read_to_end(&mut bytes)?;
    if bytes.len() > 8192 {
        return Err("settings document exceeds 8192 bytes".into());
    }

    let settings: Settings = serde_json::from_slice(&bytes)?;
    if settings.rollout_id.get_version_num() != 7
        || settings.rollout_id.get_variant() != uuid::Variant::RFC4122
        || settings.protocol_version == 0
        || settings.trusted_keys.len() > 8
    {
        return Err("invalid updater settings".into());
    }

    Ok(settings)
}

fn validate_rendezvous(path: &Path) -> std::io::Result<()> {
    if path.file_name().is_none() {
        return Err(std::io::Error::other("missing health rendezvous filename"));
    }
    match path.symlink_metadata() {
        Ok(_) => Err(std::io::Error::other("health rendezvous already exists")),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

fn check_health(candidate: &Path, rendezvous: &Path) -> bool {
    if validate_rendezvous(rendezvous).is_err() {
        return false;
    }
    let Ok(mut child) = Command::new(candidate)
        .arg("diagnose")
        .arg(rendezvous)
        .env_clear()
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    else {
        return false;
    };
    let Some(stdout) = child.stdout.take() else {
        let _ = child.kill();
        let _ = child.wait();
        return false;
    };
    let (sender, receiver) = mpsc::sync_channel(1);
    let reader = thread::spawn(move || {
        let output = BufReader::new(stdout).take(16384);
        if output
            .lines()
            .any(|line| line.is_ok_and(|line| line == HEALTH_SIGNAL))
        {
            let _ = sender.send(());
        }
    });

    let started = Instant::now();
    let healthy = loop {
        if !matches!(child.try_wait(), Ok(None)) || started.elapsed() >= HEALTH_DEADLINE {
            break false;
        }
        match receiver.recv_timeout(Duration::from_millis(25)) {
            Ok(()) => break matches!(child.try_wait(), Ok(None)),
            Err(mpsc::RecvTimeoutError::Disconnected) => break false,
            Err(mpsc::RecvTimeoutError::Timeout) => {}
        }
    };

    let _ = child.kill();
    let _ = child.wait();
    let _ = reader.join();
    if rendezvous
        .symlink_metadata()
        .is_ok_and(|metadata| metadata.is_file())
    {
        let _ = fs::remove_file(rendezvous);
    }

    healthy
}
