use std::fs::{self, File, Metadata, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use semver::Version;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tempfile::NamedTempFile;

use crate::{Channel, UpdateError, VerifiedRelease, executable::NativeFormat};

#[derive(Debug, Eq, PartialEq)]
pub enum InstallOutcome {
    Activated,
    Rejected,
}

#[derive(Debug, Eq, PartialEq)]
pub enum RollbackOutcome {
    Unavailable,
    RestoredBaseline,
    RestoredPrevious,
}

#[derive(Debug, Serialize)]
pub struct UpdateStatus {
    pub active: Option<Version>,
    pub previous: Option<Version>,
    pub highest_accepted: Option<Version>,
    pub interrupted: bool,
}

#[derive(Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Installation {
    accepted: Option<Version>,
    active: Option<Slot>,
    previous: Option<Slot>,
    pending: Option<Slot>,
    retired: Option<Slot>,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Slot {
    version: Version,
    sha256: String,
    size: u64,
}

impl Slot {
    fn path(&self, root: &Path, channel: Channel) -> PathBuf {
        root.join(format!(
            "nexbot-engine-{}-{}-{}{}",
            channel.as_str(),
            self.version,
            self.sha256,
            std::env::consts::EXE_SUFFIX,
        ))
    }

    fn validate(&self) -> Result<(), UpdateError> {
        if self.version.to_string().len() > 64
            || !self.version.build.is_empty()
            || self.sha256.len() != 64
            || hex::decode(&self.sha256).is_err()
            || !(1..=128 * 1024 * 1024).contains(&self.size)
        {
            return Err(UpdateError::State);
        }

        Ok(())
    }

    fn checked_path(&self, root: &Path, channel: Channel) -> Result<PathBuf, UpdateError> {
        let path = self.path(root, channel);
        check_file(&path)?.ok_or(UpdateError::State)?;
        copy_verified(File::open(&path)?, std::io::sink(), self.size, &self.sha256)?;
        Ok(path)
    }
}

pub struct UpdateStore {
    root: PathBuf,
    channel: Channel,
}

impl UpdateStore {
    /// Opens a private installation directory. Windows inherits its parent ACL.
    pub fn open(root: &Path, channel: Channel) -> Result<Self, UpdateError> {
        let mut builder = fs::DirBuilder::new();
        #[cfg(unix)]
        {
            use std::os::unix::fs::DirBuilderExt;
            builder.mode(0o700);
        }
        match builder.create(root) {
            Ok(()) => {}
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {}
            Err(error) => return Err(error.into()),
        }

        let metadata = root.symlink_metadata()?;
        if is_link(&metadata) || !metadata.is_dir() {
            return Err(UpdateError::State);
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            if metadata.permissions().mode() & 0o077 != 0 {
                return Err(UpdateError::State);
            }
        }

        Ok(Self {
            root: root.canonicalize()?,
            channel,
        })
    }

    pub fn status(&self) -> Result<UpdateStatus, UpdateError> {
        let _lock = self.lock()?;
        let state = self.read_state()?;
        Ok(UpdateStatus {
            active: state.active.map(|slot| slot.version),
            previous: state.previous.map(|slot| slot.version),
            highest_accepted: state.accepted,
            interrupted: state.pending.is_some(),
        })
    }

    /// Rechecks the on-disk binary before returning a path the bootstrap may launch.
    pub fn active_executable(&self) -> Result<Option<PathBuf>, UpdateError> {
        let _lock = self.lock()?;
        self.read_state()?
            .active
            .map(|slot| slot.checked_path(&self.root, self.channel))
            .transpose()
    }

    /// Reads the archive-free artifact incrementally and keeps the active slot until health passes.
    /// The caller must stop gameplay and enforce a deadline on the candidate's IPC health check.
    pub fn install(
        &self,
        release: &VerifiedRelease,
        bytes: impl Read,
        health_check: impl FnOnce(&Path) -> bool,
    ) -> Result<InstallOutcome, UpdateError> {
        release.ensure_fresh()?;
        if release.channel() != self.channel || release.target() != env!("NEXBOT_BUILD_TARGET") {
            return Err(UpdateError::Incompatible);
        }

        let _lock = self.lock()?;
        let mut state = self.read_state()?;
        if state
            .accepted
            .as_ref()
            .is_some_and(|highest| release.version() <= highest)
        {
            return Err(UpdateError::Downgrade);
        }

        self.cleanup(&mut state)?;
        if let Some(staged) = state.pending.take() {
            remove_if_present(&staged.path(&self.root, self.channel))?;
        }

        let candidate = Slot {
            version: release.version().clone(),
            sha256: release.artifact_sha256().to_owned(),
            size: release.artifact_size(),
        };

        let mut temporary = NamedTempFile::new_in(&self.root)?;
        copy_verified(
            bytes,
            temporary.as_file_mut(),
            candidate.size,
            &candidate.sha256,
        )?;
        NativeFormat::for_target(release.target())
            .ok_or(UpdateError::Integrity)?
            .check(temporary.as_file_mut())?;
        set_executable(temporary.as_file())?;
        temporary.as_file().sync_all()?;

        release.ensure_fresh()?;
        let executable = candidate.path(&self.root, self.channel);
        state.accepted = Some(candidate.version.clone());
        state.pending = Some(candidate);
        self.write_state(&state)?;

        temporary
            .persist_noclobber(&executable)
            .map_err(|error| error.error)?;
        sync_directory(&self.root)?;

        let healthy = release.ensure_fresh().is_ok()
            && health_check(&executable)
            && release.ensure_fresh().is_ok();
        let candidate = state.pending.take();
        if !healthy {
            remove_if_present(&executable)?;
            self.write_state(&state)?;
            return Ok(InstallOutcome::Rejected);
        }

        state.retired = state.previous.take();
        state.previous = state.active.take();
        state.active = candidate;
        self.write_state(&state)?;

        Ok(InstallOutcome::Activated)
    }

    /// Restores the locally retained previous slot while keeping the anti-downgrade floor.
    pub fn rollback(&self) -> Result<RollbackOutcome, UpdateError> {
        let _lock = self.lock()?;
        let mut state = self.read_state()?;
        if state.active.is_none() {
            return Ok(RollbackOutcome::Unavailable);
        }

        self.cleanup(&mut state)?;
        let previous = state.previous.take();
        if let Some(slot) = &previous {
            slot.checked_path(&self.root, self.channel)?;
        }
        let outcome = if previous.is_some() {
            RollbackOutcome::RestoredPrevious
        } else {
            RollbackOutcome::RestoredBaseline
        };
        state.retired = state.active.take();
        state.active = previous;
        self.write_state(&state)?;

        Ok(outcome)
    }

    fn cleanup(&self, state: &mut Installation) -> Result<(), UpdateError> {
        if let Some(retired) = state.retired.take() {
            remove_if_present(&retired.path(&self.root, self.channel))?;
            self.write_state(state)?;
        }
        Ok(())
    }

    fn state_path(&self) -> PathBuf {
        self.root
            .join(format!("state-{}.json", self.channel.as_str()))
    }

    fn lock(&self) -> Result<File, UpdateError> {
        let lock_path = self.root.join("update.lock");
        check_file(&lock_path)?;
        let file = OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(lock_path)?;
        file.try_lock().map_err(std::io::Error::from)?;
        Ok(file)
    }

    fn read_state(&self) -> Result<Installation, UpdateError> {
        let path = self.state_path();
        let Some(metadata) = check_file(&path)? else {
            return Ok(Installation::default());
        };
        if metadata.len() > 4096 {
            return Err(UpdateError::State);
        }
        let mut bytes = Vec::new();
        File::open(path)?.take(4097).read_to_end(&mut bytes)?;
        let state: Installation = serde_json::from_slice(&bytes).map_err(|_| UpdateError::State)?;
        for slot in [
            &state.active,
            &state.previous,
            &state.pending,
            &state.retired,
        ]
        .into_iter()
        .flatten()
        {
            slot.validate()?;
            if state
                .accepted
                .as_ref()
                .is_none_or(|floor| floor < &slot.version)
            {
                return Err(UpdateError::State);
            }
        }

        if let Some(pending) = &state.pending
            && [&state.active, &state.previous]
                .into_iter()
                .flatten()
                .any(|known| pending.version <= known.version)
        {
            return Err(UpdateError::State);
        }
        if let (Some(active), Some(previous)) = (&state.active, &state.previous)
            && previous.version >= active.version
        {
            return Err(UpdateError::State);
        }

        if let Some(retired) = &state.retired
            && [&state.active, &state.previous, &state.pending]
                .into_iter()
                .flatten()
                .any(|known| retired.version == known.version)
        {
            return Err(UpdateError::State);
        }

        Ok(state)
    }

    fn write_state(&self, state: &Installation) -> Result<(), UpdateError> {
        let path = self.state_path();
        check_file(&path)?;
        let mut temporary = NamedTempFile::new_in(&self.root)?;
        serde_json::to_writer(temporary.as_file_mut(), state).map_err(|_| UpdateError::State)?;
        temporary.as_file().sync_all()?;
        temporary.persist(&path).map_err(|error| error.error)?;
        sync_directory(&self.root)
    }
}

pub(crate) fn copy_verified(
    mut input: impl Read,
    mut output: impl Write,
    size: u64,
    sha256: &str,
) -> Result<(), UpdateError> {
    let mut remaining = size;
    let mut hash = Sha256::new();
    let mut buffer = [0; 16 * 1024];
    while remaining != 0 {
        let limit = remaining.min(buffer.len() as u64) as usize;
        let read = input.read(&mut buffer[..limit])?;
        if read == 0 {
            return Err(UpdateError::Integrity);
        }
        hash.update(&buffer[..read]);
        output.write_all(&buffer[..read])?;
        remaining -= read as u64;
    }
    if input.read(&mut buffer[..1])? != 0 || hex::encode(hash.finalize()) != sha256 {
        return Err(UpdateError::Integrity);
    }
    Ok(())
}

fn check_file(path: &Path) -> Result<Option<Metadata>, UpdateError> {
    match path.symlink_metadata() {
        Ok(metadata) if metadata.is_file() && !is_link(&metadata) => Ok(Some(metadata)),
        Ok(_) => Err(UpdateError::State),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error.into()),
    }
}

fn is_link(metadata: &Metadata) -> bool {
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;
        metadata.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0
    }
    #[cfg(not(windows))]
    metadata.file_type().is_symlink()
}

fn remove_if_present(path: &Path) -> Result<(), UpdateError> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error.into()),
    }
}

fn sync_directory(path: &Path) -> Result<(), UpdateError> {
    #[cfg(unix)]
    File::open(path)?.sync_all()?;
    // shortcut: Windows flushes staged files and uses atomic rename, add directory
    // persistence when the platform exposes an equivalent supported flush.
    #[cfg(not(unix))]
    let _ = path;
    Ok(())
}

fn set_executable(file: &File) -> Result<(), UpdateError> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        file.set_permissions(fs::Permissions::from_mode(0o500))?;
    }
    #[cfg(not(unix))]
    let _ = file;
    Ok(())
}
