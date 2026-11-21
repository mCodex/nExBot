use ed25519_dalek::SigningKey;
use nexbot_updater::{Channel, ReleaseContext, TrustAnchor, sign_manifest, verify_manifest};
use semver::Version;
use uuid::Uuid;

const MANIFEST: &[u8] = br#"{
  "schema_version": 1,
  "version": "5.1.0",
  "channel": "stable",
  "published_at": 100,
  "expires_at": 200,
  "target_triple": "x86_64-unknown-linux-gnu",
  "artifact_path": "stable/5.1.0/x86_64-unknown-linux-gnu/nexbot-engine",
  "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  "size": 3,
  "min_bridge_version": "5.0.0",
  "min_protocol_version": 1,
  "min_engine_version": "5.0.0",
  "release_id": "019af2ab-9fb3-78f1-826c-58c762793452",
  "rollout_percent": 100,
  "key_id": "test-1"
}"#;

fn release_context() -> ReleaseContext<'static> {
    ReleaseContext {
        channel: Channel::Stable,
        target: "x86_64-unknown-linux-gnu",
        engine: Version::new(5, 0, 0),
        bridge: Version::new(5, 0, 0),
        protocol: 1,
        rollout_id: Uuid::parse_str("019af2ab-9fb3-78f1-826c-58c762793452").unwrap(),
        now: 150,
    }
}

#[test]
fn signed_manifest_authenticates_the_exact_canonical_bytes() {
    let signing = SigningKey::from_bytes(&[0x53; 32]);
    let trusted = TrustAnchor {
        id: "test-1",
        key: signing.verifying_key(),
        revoked: false,
    };
    let (canonical, signature) = sign_manifest(MANIFEST, &signing).unwrap();
    let verified = verify_manifest(&canonical, &signature, &[trusted], &release_context()).unwrap();
    assert_eq!(verified.version(), &Version::new(5, 1, 0));

    let mut invalid_signature = signature;
    invalid_signature[1] ^= 1;
    assert!(
        verify_manifest(
            &canonical,
            &invalid_signature,
            &[trusted],
            &release_context()
        )
        .is_err()
    );

    let mut noncanonical = canonical;
    noncanonical.push(b' ');
    assert!(verify_manifest(&noncanonical, &signature, &[trusted], &release_context()).is_err());
}

fn verified(input: &[u8], context: &ReleaseContext<'_>) -> nexbot_updater::VerifiedRelease {
    let signing = SigningKey::from_bytes(&[0x53; 32]);
    let anchors = [TrustAnchor {
        id: "test-1",
        key: signing.verifying_key(),
        revoked: false,
    }];
    let (canonical, signature) = sign_manifest(input, &signing).unwrap();
    verify_manifest(&canonical, &signature, &anchors, context).unwrap()
}

fn native_fixture(marker: u8) -> Vec<u8> {
    let mut bytes = vec![0; 128];
    let x64 = std::env::consts::ARCH == "x86_64";
    match std::env::consts::OS {
        "linux" => {
            bytes[..7].copy_from_slice(b"\x7fELF\x02\x01\x01");
            bytes[16] = 3;
            bytes[18] = if x64 { 62 } else { 183 };
        }
        "windows" => {
            bytes[..2].copy_from_slice(b"MZ");
            bytes[60] = 64;
            bytes[64..68].copy_from_slice(b"PE\0\0");
            let machine: u16 = if x64 { 0x8664 } else { 0xaa64 };
            bytes[68..70].copy_from_slice(&machine.to_le_bytes());
            bytes[86] = 2;
            bytes[88..90].copy_from_slice(&0x20bu16.to_le_bytes());
        }
        "macos" => {
            bytes[..4].copy_from_slice(&0xfeedfacfu32.to_le_bytes());
            let cpu: u32 = if x64 { 0x01000007 } else { 0x0100000c };
            bytes[4..8].copy_from_slice(&cpu.to_le_bytes());
            bytes[12] = 2;
        }
        os => panic!("missing fixture for {os}"),
    }
    bytes[127] = marker;
    bytes
}

fn native_manifest(version: &str, artifact: &[u8]) -> nexbot_updater::VerifiedRelease {
    use sha2::{Digest, Sha256};

    let target = env!("NEXBOT_BUILD_TARGET");
    let mut input: serde_json::Value = serde_json::from_slice(MANIFEST).unwrap();
    input["version"] = version.into();
    input["target_triple"] = target.into();
    input["artifact_path"] = format!(
        "stable/{version}/{target}/nexbot-engine{}",
        std::env::consts::EXE_SUFFIX
    )
    .into();
    input["size"] = artifact.len().into();
    input["sha256"] = hex::encode(Sha256::digest(artifact)).into();
    let mut context = release_context();
    context.target = target;
    verified(&serde_json::to_vec(&input).unwrap(), &context)
}

#[test]
fn failed_health_check_preserves_active_installation_across_restarts() {
    use nexbot_updater::{InstallOutcome, UpdateError, UpdateStore};

    let root = tempfile::tempdir().unwrap();
    let first_binary = native_fixture(1);
    let first = native_manifest("5.1.0", &first_binary);
    let store = UpdateStore::open(&root.path().join("updates"), Channel::Stable).unwrap();
    let outcome = store.install(&first, first_binary.as_slice(), |candidate| {
        std::fs::read(candidate).is_ok_and(|binary| binary == first_binary)
    });
    assert!(matches!(outcome, Ok(InstallOutcome::Activated)));
    let original = store.active_executable().unwrap().unwrap();

    let next_binary = native_fixture(2);
    let next = native_manifest("5.2.0", &next_binary);
    let corrupt = store.install(&next, first_binary.as_slice(), |_| {
        panic!("corrupt binary was staged")
    });
    assert!(matches!(corrupt, Err(UpdateError::Integrity)));
    let result = store.install(&next, next_binary.as_slice(), |_| false);
    assert!(matches!(result, Ok(InstallOutcome::Rejected)));

    let reopened = UpdateStore::open(&root.path().join("updates"), Channel::Stable).unwrap();
    assert_eq!(reopened.active_executable().unwrap().unwrap(), original);
    assert!(matches!(
        reopened.install(&next, next_binary.as_slice(), |_| true),
        Err(UpdateError::Downgrade)
    ));
}

#[test]
fn transport_rejects_unsafe_project_urls_before_opening_a_connection() {
    use nexbot_updater::ReleaseTransport;

    for url in [
        "http://updates.example.org",
        "https://username:password@updates.example.org",
        "https://updates.example.org:9443",
        "https://updates.example.org/functions/v1",
        "https://updates.example.org/?token=secret",
    ] {
        assert!(
            ReleaseTransport::new(url, "/api/update-check", "/signed/releases/").is_err(),
            "{url}"
        );
    }
    assert!(
        ReleaseTransport::new(
            "https://updates.example.org",
            "/api/update-check",
            "/signed/releases/"
        )
        .is_ok()
    );
}

#[test]
fn verified_but_non_native_payload_is_never_executed() {
    use nexbot_updater::{UpdateError, UpdateStore};

    let root = tempfile::tempdir().unwrap();
    let release = native_manifest("5.1.0", b"abc");
    let store = UpdateStore::open(&root.path().join("updates"), Channel::Stable).unwrap();
    let outcome = store.install(&release, &b"abc"[..], |_| {
        panic!("invalid executable was launched")
    });
    assert!(matches!(outcome, Err(UpdateError::Integrity)));
}

#[test]
fn local_rollback_restores_previous_then_baseline_without_lowering_the_floor() {
    use nexbot_updater::{InstallOutcome, RollbackOutcome, UpdateError, UpdateStore};

    let root = tempfile::tempdir().unwrap();
    let store = UpdateStore::open(&root.path().join("updates"), Channel::Stable).unwrap();
    let first = native_fixture(1);
    let second = native_fixture(2);
    let release_one = native_manifest("5.1.0", &first);
    let release_two = native_manifest("5.2.0", &second);

    assert_eq!(
        store
            .install(&release_one, first.as_slice(), |_| true)
            .unwrap(),
        InstallOutcome::Activated
    );
    assert_eq!(
        store
            .install(&release_two, second.as_slice(), |_| true)
            .unwrap(),
        InstallOutcome::Activated
    );

    assert_eq!(store.rollback().unwrap(), RollbackOutcome::RestoredPrevious);
    assert_eq!(
        std::fs::read(store.active_executable().unwrap().unwrap()).unwrap(),
        first
    );
    assert_eq!(store.rollback().unwrap(), RollbackOutcome::RestoredBaseline);
    assert!(store.active_executable().unwrap().is_none());
    assert_eq!(store.rollback().unwrap(), RollbackOutcome::Unavailable);
    assert!(matches!(
        store.install(&release_two, second.as_slice(), |_| true),
        Err(UpdateError::Downgrade)
    ));
}

#[test]
fn crash_during_qualification_keeps_the_old_slot_and_persists_the_update_floor() {
    use nexbot_updater::{InstallOutcome, UpdateStore};

    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("updates");
    let first = native_fixture(1);
    let second = native_fixture(2);
    let release_one = native_manifest("5.1.0", &first);
    let release_two = native_manifest("5.2.0", &second);
    let store = UpdateStore::open(&path, Channel::Stable).unwrap();
    assert_eq!(
        store
            .install(&release_one, first.as_slice(), |_| true)
            .unwrap(),
        InstallOutcome::Activated
    );

    let failure = std::panic::catch_unwind(|| {
        let _ = store.install(&release_two, second.as_slice(), |_| {
            panic!("simulated power loss")
        });
    });
    assert!(failure.is_err());

    let reopened = UpdateStore::open(&path, Channel::Stable).unwrap();
    let status = reopened.status().unwrap();
    assert!(status.interrupted);
    assert_eq!(status.active.unwrap(), Version::new(5, 1, 0));
    assert_eq!(status.highest_accepted.unwrap(), Version::new(5, 2, 0));
    assert_eq!(
        std::fs::read(reopened.active_executable().unwrap().unwrap()).unwrap(),
        first
    );
}

#[test]
fn revoked_keys_incompatible_releases_and_expired_metadata_fail_closed() {
    use nexbot_updater::UpdateError;

    let signing = SigningKey::from_bytes(&[0x53; 32]);
    let trusted = TrustAnchor {
        id: "test-1",
        key: signing.verifying_key(),
        revoked: false,
    };
    let revoked = TrustAnchor {
        revoked: true,
        ..trusted
    };
    let (canonical, signature) = sign_manifest(MANIFEST, &signing).unwrap();
    let verify = |anchors: &[TrustAnchor<'_>], context: ReleaseContext<'_>| {
        verify_manifest(&canonical, &signature, anchors, &context)
    };

    assert!(matches!(
        verify(&[], release_context()),
        Err(UpdateError::Trust)
    ));
    assert!(matches!(
        verify(&[revoked], release_context()),
        Err(UpdateError::Trust)
    ));
    assert!(matches!(
        verify(&[trusted, trusted], release_context()),
        Err(UpdateError::Trust)
    ));

    assert!(matches!(
        verify(
            &[trusted],
            ReleaseContext {
                now: 200,
                ..release_context()
            }
        ),
        Err(UpdateError::Time)
    ));
    assert!(matches!(
        verify(
            &[trusted],
            ReleaseContext {
                channel: Channel::Beta,
                ..release_context()
            }
        ),
        Err(UpdateError::Incompatible)
    ));
    assert!(matches!(
        verify(
            &[trusted],
            ReleaseContext {
                target: "aarch64-apple-darwin",
                ..release_context()
            }
        ),
        Err(UpdateError::Incompatible)
    ));
    assert!(matches!(
        verify(
            &[trusted],
            ReleaseContext {
                protocol: 0,
                ..release_context()
            }
        ),
        Err(UpdateError::Incompatible)
    ));
    assert!(matches!(
        verify(
            &[trusted],
            ReleaseContext {
                bridge: Version::new(4, 9, 0),
                ..release_context()
            }
        ),
        Err(UpdateError::Incompatible)
    ));
    assert!(matches!(
        verify(
            &[trusted],
            ReleaseContext {
                engine: Version::new(4, 9, 0),
                ..release_context()
            }
        ),
        Err(UpdateError::Incompatible)
    ));
    assert!(matches!(
        verify(
            &[trusted],
            ReleaseContext {
                engine: Version::new(5, 1, 0),
                ..release_context()
            }
        ),
        Err(UpdateError::Downgrade)
    ));

    let paused = str::from_utf8(MANIFEST)
        .unwrap()
        .replace("\"rollout_percent\": 100", "\"rollout_percent\": 0");
    let (canonical, signature) = sign_manifest(paused.as_bytes(), &signing).unwrap();
    assert!(matches!(
        verify_manifest(&canonical, &signature, &[trusted], &release_context()),
        Err(UpdateError::Rollout)
    ));
}

#[test]
fn signer_rejects_oversized_corrupt_or_non_native_artifacts() {
    use nexbot_updater::{UpdateError, sign_artifact};
    use std::io::Cursor;

    let signing = SigningKey::from_bytes(&[0x53; 32]);
    for bytes in [b"" as &[u8], b"abc", b"abcdef", b"xyz"] {
        assert!(matches!(
            sign_artifact(MANIFEST, Cursor::new(bytes), &signing),
            Err(UpdateError::Integrity)
        ));
    }
}

#[cfg(unix)]
#[test]
fn symlinked_update_root_or_state_fails_before_following_the_link() {
    use nexbot_updater::{UpdateError, UpdateStore};
    use std::os::unix::fs::symlink;

    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("updates");
    let decoy = root.path().join("decoy");
    symlink(&decoy, &path).unwrap();
    assert!(matches!(
        UpdateStore::open(&path, Channel::Stable),
        Err(UpdateError::State)
    ));

    let valid = root.path().join("valid");
    let store = UpdateStore::open(&valid, Channel::Stable).unwrap();
    symlink(&decoy, valid.join("state-stable.json")).unwrap();
    assert!(matches!(store.status(), Err(UpdateError::State)));
    assert!(!decoy.exists());
}

#[test]
fn store_rejects_busy_or_malformed_state_and_checks_active_bytes_again() {
    use nexbot_updater::{InstallOutcome, UpdateError, UpdateStore};

    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().join("updates");
    let store = UpdateStore::open(&root, Channel::Stable).unwrap();
    let binary = native_fixture(1);
    let release = native_manifest("5.1.0", &binary);

    let install = store.install(&release, binary.as_slice(), |_| {
        assert!(matches!(store.status(), Err(UpdateError::Io(_))));
        true
    });
    assert_eq!(install.unwrap(), InstallOutcome::Activated);

    let executable = store.active_executable().unwrap().unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&executable, std::fs::Permissions::from_mode(0o600)).unwrap();
    }
    std::fs::write(executable, b"corrupt").unwrap();
    assert!(matches!(
        store.active_executable(),
        Err(UpdateError::Integrity)
    ));

    let state = root.join("state-stable.json");
    std::fs::write(&state, b"{}bad").unwrap();
    assert!(matches!(store.status(), Err(UpdateError::State)));
    std::fs::write(&state, vec![b' '; 4097]).unwrap();
    assert!(matches!(store.status(), Err(UpdateError::State)));
}

#[test]
fn transport_rejects_ambiguous_or_cross_origin_configured_paths() {
    use nexbot_updater::ReleaseTransport;

    for invalid in [
        "//other.example.org/api",
        "/api/../updates",
        "/api/%2e%2e",
        "/api?update=1",
        "/api#check",
        "relative",
    ] {
        assert!(
            ReleaseTransport::new("https://updates.example.org", invalid, "/signed/releases/")
                .is_err()
        );
    }
    assert!(
        ReleaseTransport::new(
            "https://updates.example.org",
            "/api/update-check",
            "/signed/releases"
        )
        .is_err()
    );
}

#[test]
fn signer_rejects_malformed_manifest_fields_without_producing_a_signature() {
    use nexbot_updater::UpdateError;
    use serde_json::json;

    let signing = SigningKey::from_bytes(&[0x53; 32]);
    let template: serde_json::Value = serde_json::from_slice(MANIFEST).unwrap();
    for (field, invalid) in [
        ("schema_version", json!(2)),
        ("version", json!("5.1.0+build")),
        ("version", json!("5.1.0-beta.1")),
        ("min_engine_version", json!("9.1.2")),
        ("min_engine_version", json!("5.0.0+build")),
        ("min_bridge_version", json!("5.0.0+build")),
        ("published_at", json!(0)),
        ("expires_at", json!(100)),
        ("expires_at", json!(3_000_000)),
        ("target_triple", json!("unsupported-target")),
        ("artifact_path", json!("../../executable")),
        ("key_id", json!("")),
        ("key_id", json!("../key")),
        ("sha256", json!("wrong-length")),
        ("sha256", json!("Z".repeat(64))),
        ("size", json!(0)),
        ("size", json!(128 * 1024 * 1024 + 1)),
        ("min_protocol_version", json!(0)),
        ("release_id", json!("00000000-0000-4000-8000-123456789abc")),
        ("release_id", json!("00000000-0000-7000-0000-123456789abc")),
        ("rollout_percent", json!(101)),
        ("unknown", json!(true)),
    ] {
        let mut changed = template.clone();
        changed[field] = invalid;
        let bytes = serde_json::to_vec(&changed).unwrap();
        assert!(
            matches!(sign_manifest(&bytes, &signing), Err(UpdateError::Manifest)),
            "{field}"
        );
    }
    let oversized = vec![b' '; nexbot_updater::MAX_MANIFEST_BYTES + 1];
    assert!(matches!(
        sign_manifest(&oversized, &signing),
        Err(UpdateError::Manifest)
    ));
}
