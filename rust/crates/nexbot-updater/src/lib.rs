#![forbid(unsafe_code)]

mod executable;
mod manifest;
mod store;
mod transport;

pub use manifest::{
    Channel, MAX_MANIFEST_BYTES, ReleaseContext, TrustAnchor, VerifiedRelease, sign_artifact,
    sign_manifest, verify_manifest,
};

pub use store::{InstallOutcome, RollbackOutcome, UpdateStatus, UpdateStore};
pub use transport::{AvailableUpdate, ReleaseTransport};

#[derive(Debug, thiserror::Error)]
pub enum UpdateError {
    #[error("invalid release manifest")]
    Manifest,
    #[error("release signing key is unknown or revoked")]
    Trust,
    #[error("invalid release signature")]
    Signature,
    #[error("release is incompatible with this installation")]
    Incompatible,
    #[error("release is outside its publication or expiry window")]
    Time,
    #[error("release is outside this installation's rollout")]
    Rollout,
    #[error("release would repeat or downgrade an accepted version")]
    Downgrade,
    #[error("artifact size or checksum does not match the release manifest")]
    Integrity,
    #[error("invalid local update state or filesystem entry")]
    State,
    #[error("invalid release service origin or signed storage URL")]
    Origin,
    #[error("release service is unavailable or returned an invalid response")]
    Network,
    #[error("filesystem or streaming I/O failed: {0}")]
    Io(#[from] std::io::Error),
}
