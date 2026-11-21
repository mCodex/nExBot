use std::fs::{self, File};
use std::io::Read;
use std::path::Path;
use std::process::{Command, Output};

use ed25519_dalek::SigningKey;
use nexbot_updater::{Channel, ReleaseContext, TrustAnchor, verify_manifest};
use semver::Version;
use serde_json::json;
use sha2::{Digest, Sha256};
use uuid::Uuid;

const BOOTSTRAP: &str = env!("CARGO_BIN_EXE_nexbot-bootstrap");
const PUBLISHER: &str = env!("CARGO_BIN_EXE_release-publisher");
const RELEASE_ID: &str = "019af2ab-9fb3-78f1-826c-58c762793452";

fn command(path: &str, args: &[&Path]) -> Output {
    Command::new(path).args(args).output().unwrap()
}

fn bootstrap(command_name: &str, store: &Path, settings: &Path) -> Output {
    command(BOOTSTRAP, &[Path::new(command_name), store, settings])
}

fn error(output: Output, expected: &str) {
    assert!(!output.status.success(), "{output:?}");
    let stderr = String::from_utf8(output.stderr).unwrap();
    assert!(stderr.contains(expected), "{stderr}");
}

fn write_settings(path: &Path, key: bool, service_url: &str) {
    let configured = if key {
        vec![json!({
            "id": "fixture-1",
            "public_key_hex": hex::encode(SigningKey::from_bytes(&[31; 32]).verifying_key().to_bytes()),
            "revoked": false,
        })]
    } else {
        Vec::new()
    };
    let data = serde_json::to_vec(&json!({
        "service_url": service_url,
        "check_path": "/api/update-check",
        "signed_objects_prefix": "/signed/releases/",
        "channel": "stable",
        "baseline_engine_version": "5.0.0",
        "bridge_version": "5.0.0",
        "protocol_version": 1,
        "rollout_id": RELEASE_ID,
        "trusted_keys": configured,
    }))
    .unwrap();
    fs::write(path, data).unwrap();
}

#[test]
fn bootstrap_reports_version_status_rollback_and_fallback() {
    let version = command(BOOTSTRAP, &[Path::new("--version")]);
    assert!(version.status.success(), "{version:?}");
    assert!(version.stdout.starts_with(b"nexbot-bootstrap "));

    let temp = tempfile::tempdir().unwrap();
    let store = temp.path().join("updates");
    let settings = temp.path().join("settings.json");
    write_settings(&settings, false, "https://updates.example.org");

    let status = bootstrap("status", &store, &settings);
    assert!(status.status.success(), "{status:?}");
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&status.stdout).unwrap(),
        json!({"active": null, "previous": null, "highest_accepted": null, "interrupted": false})
    );
    let active = bootstrap("active-path", &store, &settings);
    assert!(active.status.success());
    assert!(active.stdout.is_empty());

    let rollback = bootstrap("rollback", &store, &settings);
    assert!(rollback.status.success());
    assert_eq!(rollback.stdout, b"no installed update to undo\n");
}

#[test]
fn bootstrap_rejects_missing_malformed_or_unsafe_updater_settings() {
    let temp = tempfile::tempdir().unwrap();
    let store = temp.path().join("updates");
    let settings = temp.path().join("settings.json");

    error(command(BOOTSTRAP, &[]), "usage:");
    error(bootstrap("status", &store, &settings), "nExBot bootstrap:");
    fs::write(&settings, vec![b' '; 8193]).unwrap();
    error(bootstrap("status", &store, &settings), "exceeds 8192 bytes");

    write_settings(&settings, false, "https://updates.example.org");
    error(
        bootstrap("check", &store, &settings),
        "no trusted release key",
    );

    write_settings(&settings, true, "http://updates.example.org");
    error(
        bootstrap("check", &store, &settings),
        "invalid release service origin",
    );
}

#[test]
fn offline_publisher_signs_and_verifies_the_compiled_native_binary() {
    let temp = tempfile::tempdir().unwrap();
    let seed_path = temp.path().join("fixture-seed");
    let metadata_path = temp.path().join("metadata.json");
    let artifact = std::env::current_exe().unwrap();
    let mut executable = File::open(&artifact).unwrap();
    let mut hash = Sha256::new();
    let mut block = [0; 16_384];
    loop {
        let count = executable.read(&mut block).unwrap();
        if count == 0 {
            break;
        }
        hash.update(&block[..count]);
    }

    let target = env!("NEXBOT_BUILD_TARGET");
    let object_path = format!(
        "stable/5.1.0/{target}/nexbot-engine{}",
        std::env::consts::EXE_SUFFIX
    );
    fs::write(
        &metadata_path,
        serde_json::to_vec_pretty(&json!({
            "schema_version": 1,
            "version": "5.1.0",
            "channel": "stable",
            "published_at": 100,
            "expires_at": 200,
            "target_triple": target,
            "artifact_path": object_path,
            "sha256": hex::encode(hash.finalize()),
            "size": executable.metadata().unwrap().len(),
            "min_bridge_version": "5.0.0",
            "min_protocol_version": 1,
            "min_engine_version": "5.0.0",
            "release_id": RELEASE_ID,
            "rollout_percent": 100,
            "key_id": "fixture-1"
        }))
        .unwrap(),
    )
    .unwrap();

    let args = [
        Path::new("sign"),
        &seed_path,
        &metadata_path,
        &artifact,
        temp.path(),
    ];
    fs::write(&seed_path, [31; 33]).unwrap();
    error(command(PUBLISHER, &args), "raw, 32-byte Ed25519 key seed");
    fs::write(&seed_path, [31; 32]).unwrap();
    let publication = command(PUBLISHER, &args);
    assert!(publication.status.success(), "{publication:?}");

    let signature = fs::read(temp.path().join("manifest.sig")).unwrap();
    let manifest = fs::read(temp.path().join("manifest.json")).unwrap();
    let release = verify_manifest(
        &manifest,
        &signature,
        &[TrustAnchor {
            id: "fixture-1",
            key: SigningKey::from_bytes(&[31; 32]).verifying_key(),
            revoked: false,
        }],
        &ReleaseContext {
            channel: Channel::Stable,
            target,
            engine: Version::new(5, 0, 0),
            bridge: Version::new(5, 0, 0),
            protocol: 1,
            rollout_id: Uuid::parse_str(RELEASE_ID).unwrap(),
            now: 150,
        },
    )
    .unwrap();
    assert_eq!(release.artifact_path(), object_path);
    assert_eq!(signature.len(), 64);
    assert!(!command(PUBLISHER, &args).status.success());
    assert_eq!(
        fs::read(temp.path().join("manifest.json")).unwrap(),
        manifest
    );
}
