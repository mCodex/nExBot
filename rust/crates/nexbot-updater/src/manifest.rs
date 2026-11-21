use std::io::{Read, Seek};
use std::time::{Duration, Instant};

use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use semver::Version;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::{UpdateError, executable::NativeFormat, store::copy_verified};

pub const MAX_MANIFEST_BYTES: usize = 4096;
const MAX_ARTIFACT_BYTES: u64 = 128 * 1024 * 1024;
const MAX_LIFETIME_SECS: u64 = 31 * 24 * 60 * 60;
const CLOCK_SKEW_SECS: u64 = 300;
const SIGNATURE_CONTEXT: &[u8] = b"nexbot-release-manifest/v1\0";

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Channel {
    Stable,
    Beta,
    Nightly,
}

impl Channel {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Stable => "stable",
            Self::Beta => "beta",
            Self::Nightly => "nightly",
        }
    }
}

#[derive(Clone, Copy)]
pub struct TrustAnchor<'a> {
    pub id: &'a str,
    pub key: VerifyingKey,
    pub revoked: bool,
}

pub struct ReleaseContext<'a> {
    pub channel: Channel,
    pub target: &'a str,
    pub engine: Version,
    pub bridge: Version,
    pub protocol: u16,
    pub rollout_id: Uuid,
    pub now: u64,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Manifest {
    schema_version: u16,
    version: Version,
    channel: Channel,
    published_at: u64,
    expires_at: u64,
    target_triple: String,
    artifact_path: String,
    sha256: String,
    size: u64,
    min_bridge_version: Version,
    min_protocol_version: u16,
    min_engine_version: Version,
    release_id: Uuid,
    rollout_percent: u8,
    key_id: String,
}

#[derive(Debug)]
pub struct VerifiedRelease {
    manifest: Manifest,
    verified_at: Instant,
    lifetime: Duration,
}

impl VerifiedRelease {
    pub(crate) fn ensure_fresh(&self) -> Result<(), UpdateError> {
        if self.verified_at.elapsed() >= self.lifetime {
            return Err(UpdateError::Time);
        }
        Ok(())
    }

    pub fn version(&self) -> &Version {
        &self.manifest.version
    }

    pub fn channel(&self) -> Channel {
        self.manifest.channel
    }

    pub fn target(&self) -> &str {
        &self.manifest.target_triple
    }

    pub fn artifact_path(&self) -> &str {
        &self.manifest.artifact_path
    }

    pub fn artifact_size(&self) -> u64 {
        self.manifest.size
    }

    pub fn artifact_sha256(&self) -> &str {
        &self.manifest.sha256
    }
}

impl Manifest {
    pub(crate) fn check_window(&self, now: u64) -> Result<(), UpdateError> {
        if self.published_at > now.saturating_add(CLOCK_SKEW_SECS) || self.expires_at <= now {
            return Err(UpdateError::Time);
        }
        Ok(())
    }

    fn parse(bytes: &[u8]) -> Result<Self, UpdateError> {
        if bytes.len() > MAX_MANIFEST_BYTES {
            return Err(UpdateError::Manifest);
        }

        let manifest: Self = serde_json::from_slice(bytes).map_err(|_| UpdateError::Manifest)?;
        manifest.validate()?;
        Ok(manifest)
    }

    fn canonical_bytes(&self) -> Result<Vec<u8>, UpdateError> {
        serde_json::to_vec(self).map_err(|_| UpdateError::Manifest)
    }

    fn validate(&self) -> Result<(), UpdateError> {
        if self.schema_version != 1
            || !valid_version(&self.version)
            || !valid_version(&self.min_bridge_version)
            || !valid_version(&self.min_engine_version)
            || self.min_engine_version >= self.version
            || (self.channel == Channel::Stable && !self.version.pre.is_empty())
            || self.published_at == 0
            || self.expires_at <= self.published_at
            || self.expires_at - self.published_at > MAX_LIFETIME_SECS
            || NativeFormat::for_target(&self.target_triple).is_none()
            || !identifier(&self.key_id, 32)
            || self.sha256.len() != 64
            || !self
                .sha256
                .bytes()
                .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
            || !(1..=MAX_ARTIFACT_BYTES).contains(&self.size)
            || self.min_protocol_version == 0
            || self.release_id.get_version_num() != 7
            || self.release_id.get_variant() != uuid::Variant::RFC4122
            || self.rollout_percent > 100
        {
            return Err(UpdateError::Manifest);
        }

        let filename = if self.target_triple.contains("-windows-") {
            "nexbot-engine.exe"
        } else {
            "nexbot-engine"
        };
        let expected_path = format!(
            "{}/{}/{}/{}",
            self.channel.as_str(),
            self.version,
            self.target_triple,
            filename
        );

        if self.artifact_path != expected_path {
            return Err(UpdateError::Manifest);
        }

        Ok(())
    }
}

fn valid_version(version: &Version) -> bool {
    version.build.is_empty() && version.to_string().len() <= 64
}

fn identifier(value: &str, max: usize) -> bool {
    !value.is_empty()
        && value.len() <= max
        && value.bytes().all(|byte| {
            byte.is_ascii_lowercase() || byte.is_ascii_digit() || matches!(byte, b'_' | b'-')
        })
}

fn message(bytes: &[u8]) -> Vec<u8> {
    [SIGNATURE_CONTEXT, bytes].concat()
}

/// Normalizes and signs a release metadata document. Keep the signing key offline.
pub fn sign_manifest(bytes: &[u8], key: &SigningKey) -> Result<(Vec<u8>, [u8; 64]), UpdateError> {
    sign(&Manifest::parse(bytes)?, key)
}

/// Checks the release binary while signing canonical release metadata.
pub fn sign_artifact(
    bytes: &[u8],
    mut artifact: impl Read + Seek,
    key: &SigningKey,
) -> Result<(Vec<u8>, [u8; 64]), UpdateError> {
    let manifest = Manifest::parse(bytes)?;
    copy_verified(
        &mut artifact,
        std::io::sink(),
        manifest.size,
        &manifest.sha256,
    )?;
    NativeFormat::for_target(&manifest.target_triple)
        .ok_or(UpdateError::Manifest)?
        .check(artifact)?;
    sign(&manifest, key)
}

fn sign(manifest: &Manifest, key: &SigningKey) -> Result<(Vec<u8>, [u8; 64]), UpdateError> {
    let canonical = manifest.canonical_bytes()?;
    let signature = key.sign(&message(&canonical)).to_bytes();

    Ok((canonical, signature))
}

/// Uses the release key ID only to select a locally configured trust anchor.
pub fn verify_manifest(
    bytes: &[u8],
    signature: &[u8],
    anchors: &[TrustAnchor<'_>],
    context: &ReleaseContext<'_>,
) -> Result<VerifiedRelease, UpdateError> {
    let manifest = authenticate(bytes, signature, anchors)?;
    manifest.check_window(context.now)?;

    if manifest.channel != context.channel
        || manifest.target_triple != context.target
        || manifest
            .min_bridge_version
            .cmp_precedence(&context.bridge)
            .is_gt()
        || manifest
            .min_engine_version
            .cmp_precedence(&context.engine)
            .is_gt()
        || manifest.min_protocol_version > context.protocol
    {
        return Err(UpdateError::Incompatible);
    }
    if !manifest.version.cmp_precedence(&context.engine).is_gt() {
        return Err(UpdateError::Downgrade);
    }

    let rollout = Sha256::digest(context.rollout_id.hyphenated().to_string().as_bytes());
    let bucket = u32::from_be_bytes([rollout[0], rollout[1], rollout[2], rollout[3]]) % 100;
    if bucket >= u32::from(manifest.rollout_percent) {
        return Err(UpdateError::Rollout);
    }

    Ok(VerifiedRelease {
        lifetime: Duration::from_secs(manifest.expires_at - context.now),
        manifest,
        verified_at: Instant::now(),
    })
}

fn authenticate(
    bytes: &[u8],
    signature: &[u8],
    anchors: &[TrustAnchor<'_>],
) -> Result<Manifest, UpdateError> {
    let manifest = Manifest::parse(bytes)?;
    if manifest.canonical_bytes()? != bytes {
        return Err(UpdateError::Manifest);
    }

    let mut matches = anchors.iter().filter(|anchor| anchor.id == manifest.key_id);
    let anchor = matches.next().ok_or(UpdateError::Trust)?;
    if anchor.revoked || matches.next().is_some() {
        return Err(UpdateError::Trust);
    }

    let signature = Signature::from_slice(signature).map_err(|_| UpdateError::Signature)?;
    anchor
        .key
        .verify_strict(&message(bytes), &signature)
        .map_err(|_| UpdateError::Signature)?;

    Ok(manifest)
}
