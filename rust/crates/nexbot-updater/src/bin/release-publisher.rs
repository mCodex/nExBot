#![forbid(unsafe_code)]

use std::error::Error;
use std::fs::File;
use std::io::{Read, Write};
use std::path::Path;

use ed25519_dalek::SigningKey;
use nexbot_updater::{MAX_MANIFEST_BYTES, sign_artifact};
use tempfile::NamedTempFile;
use zeroize::Zeroizing;

fn main() -> Result<(), Box<dyn Error>> {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    let [command, key_path, metadata_path, artifact_path, output] = args.as_slice() else {
        return Err(
            "usage: release-publisher sign KEY_SEED_FILE METADATA_JSON ARTIFACT OUTPUT_DIR".into(),
        );
    };

    if command != "sign" {
        return Err("expected sign".into());
    }

    let mut seed = Zeroizing::new([0u8; 32]);
    let mut key_file = File::open(key_path)?;
    key_file.read_exact(seed.as_mut())?;
    if key_file.read(&mut [0; 1])? != 0 {
        return Err("expected a raw, 32-byte Ed25519 key seed".into());
    }
    let signing_key = SigningKey::from_bytes(&seed);

    let mut metadata = Vec::new();
    File::open(metadata_path)?
        .take((MAX_MANIFEST_BYTES + 1) as u64)
        .read_to_end(&mut metadata)?;

    let (canonical, signature) =
        sign_artifact(&metadata, File::open(artifact_path)?, &signing_key)?;
    let output = Path::new(output);
    let mut metadata_file = NamedTempFile::new_in(output)?;
    metadata_file.write_all(&canonical)?;
    metadata_file.as_file().sync_all()?;
    let mut signature_file = NamedTempFile::new_in(output)?;
    signature_file.write_all(&signature)?;
    signature_file.as_file().sync_all()?;

    signature_file.persist_noclobber(output.join("manifest.sig"))?;
    metadata_file.persist_noclobber(output.join("manifest.json"))?;
    #[cfg(unix)]
    File::open(output)?.sync_all()?;

    Ok(())
}
