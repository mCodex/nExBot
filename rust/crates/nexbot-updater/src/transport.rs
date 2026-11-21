use std::io::Read;
use std::path::Path;
use std::time::Duration;

use reqwest::Url;
use reqwest::blocking::{Client, Response};
use serde::{Deserialize, Serialize};

use crate::{
    Channel, InstallOutcome, MAX_MANIFEST_BYTES, ReleaseContext, TrustAnchor, UpdateError,
    UpdateStore, VerifiedRelease, verify_manifest,
};

pub struct ReleaseTransport {
    origin: Url,
    check_url: Url,
    signed_objects_prefix: String,
    client: Client,
}

pub struct AvailableUpdate<'a> {
    release: VerifiedRelease,
    artifact_url: Url,
    transport: &'a ReleaseTransport,
}

#[derive(Serialize)]
struct CheckRequest<'a> {
    current_version: &'a semver::Version,
    channel: Channel,
    target_triple: &'a str,
    protocol_version: u16,
    bridge_version: &'a semver::Version,
    rollout_id: uuid::Uuid,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct CheckResponse {
    available: bool,
    artifact_url: Option<String>,
    manifest_url: Option<String>,
    signature_url: Option<String>,
}

impl ReleaseTransport {
    /// Uses a locally configured HTTPS origin and exact release routes. Redirects and environment proxies are disabled.
    pub fn new(
        service_url: &str,
        check_path: &str,
        signed_objects_prefix: &str,
    ) -> Result<Self, UpdateError> {
        let origin = Url::parse(service_url).map_err(|_| UpdateError::Origin)?;
        if origin.scheme() != "https"
            || origin.host_str().is_none()
            || !origin.username().is_empty()
            || origin.password().is_some()
            || origin.port().is_some()
            || origin.path() != "/"
            || origin.query().is_some()
            || origin.fragment().is_some()
        {
            return Err(UpdateError::Origin);
        }

        if !valid_path(check_path)
            || !valid_path(signed_objects_prefix)
            || !signed_objects_prefix.ends_with('/')
        {
            return Err(UpdateError::Origin);
        }
        let check_url = origin.join(check_path).map_err(|_| UpdateError::Origin)?;

        let client = Client::builder()
            .https_only(true)
            .no_proxy()
            .redirect(reqwest::redirect::Policy::none())
            .connect_timeout(Duration::from_secs(5))
            .timeout(Duration::from_secs(30))
            .build()
            .map_err(|_| UpdateError::Network)?;

        Ok(Self {
            origin,
            check_url,
            signed_objects_prefix: signed_objects_prefix.to_owned(),
            client,
        })
    }

    /// Fetches bounded release metadata, then verifies authenticity and compatibility locally.
    pub fn check(
        &self,
        context: &ReleaseContext<'_>,
        anchors: &[TrustAnchor<'_>],
    ) -> Result<Option<AvailableUpdate<'_>>, UpdateError> {
        let request = CheckRequest {
            current_version: &context.engine,
            channel: context.channel,
            target_triple: context.target,
            protocol_version: context.protocol,
            bridge_version: &context.bridge,
            rollout_id: context.rollout_id,
        };
        let response = successful(
            self.client
                .post(self.check_url.clone())
                .json(&request)
                .send(),
        )?;
        let bytes = read_bounded(response, 8192)?;
        let response: CheckResponse =
            serde_json::from_slice(&bytes).map_err(|_| UpdateError::Network)?;

        let (artifact_url, manifest_url, signature_url) = match response {
            CheckResponse {
                available: true,
                artifact_url: Some(artifact),
                manifest_url: Some(manifest),
                signature_url: Some(signature),
            } => (
                self.storage_url(&artifact)?,
                self.storage_url(&manifest)?,
                self.storage_url(&signature)?,
            ),
            CheckResponse {
                available: false,
                artifact_url: None,
                manifest_url: None,
                signature_url: None,
            } => return Ok(None),
            _ => return Err(UpdateError::Network),
        };

        let manifest = read_bounded(self.download(manifest_url.clone())?, MAX_MANIFEST_BYTES)?;
        let signature = read_bounded(self.download(signature_url.clone())?, 64)?;
        let release = verify_manifest(&manifest, &signature, anchors, context)?;
        let (prefix, _) = release
            .artifact_path()
            .rsplit_once('/')
            .ok_or(UpdateError::Manifest)?;

        let signed = &self.signed_objects_prefix;
        if artifact_url.path() != format!("{signed}{}", release.artifact_path())
            || manifest_url.path() != format!("{signed}{prefix}/manifest.json")
            || signature_url.path() != format!("{signed}{prefix}/manifest.sig")
        {
            return Err(UpdateError::Origin);
        }

        Ok(Some(AvailableUpdate {
            release,
            artifact_url,
            transport: self,
        }))
    }

    fn storage_url(&self, input: &str) -> Result<Url, UpdateError> {
        let candidate = Url::parse(input).map_err(|_| UpdateError::Origin)?;
        if candidate.origin() != self.origin.origin()
            || !candidate.username().is_empty()
            || candidate.password().is_some()
            || candidate.fragment().is_some()
            || !candidate.path().starts_with(&self.signed_objects_prefix)
        {
            return Err(UpdateError::Origin);
        }

        let mut query = candidate.query_pairs();
        if !query
            .next()
            .is_some_and(|(key, token)| key == "token" && !token.is_empty())
            || query.next().is_some()
        {
            return Err(UpdateError::Origin);
        }

        Ok(candidate)
    }

    fn download(&self, url: Url) -> Result<Response, UpdateError> {
        successful(self.client.get(url).send())
    }
}

impl AvailableUpdate<'_> {
    pub fn version(&self) -> &semver::Version {
        self.release.version()
    }

    /// Streams a signed artifact directly to the installation store.
    /// Use immediately after the update check because the storage grant expires.
    pub fn install(
        self,
        store: &UpdateStore,
        health_check: impl FnOnce(&Path) -> bool,
    ) -> Result<InstallOutcome, UpdateError> {
        let response = self.transport.download(self.artifact_url)?;
        if response
            .content_length()
            .is_some_and(|len| len != self.release.artifact_size())
        {
            return Err(UpdateError::Integrity);
        }

        store.install(&self.release, ArtifactStream(response), health_check)
    }
}

struct ArtifactStream(Response);

impl Read for ArtifactStream {
    fn read(&mut self, bytes: &mut [u8]) -> std::io::Result<usize> {
        self.0
            .read(bytes)
            .map_err(|error| std::io::Error::new(error.kind(), "artifact download interrupted"))
    }
}

fn successful(response: Result<Response, reqwest::Error>) -> Result<Response, UpdateError> {
    response
        .ok()
        .filter(|response| response.status().is_success())
        .ok_or(UpdateError::Network)
}

fn read_bounded(response: Response, limit: usize) -> Result<Vec<u8>, UpdateError> {
    let mut bytes = Vec::new();
    response
        .take((limit + 1) as u64)
        .read_to_end(&mut bytes)
        .map_err(|_| UpdateError::Network)?;
    if bytes.len() > limit {
        return Err(UpdateError::Network);
    }
    Ok(bytes)
}

fn valid_path(path: &str) -> bool {
    path.len() <= 256
        && path.starts_with('/')
        && !path.contains("//")
        && !path.split('/').any(|segment| matches!(segment, "." | ".."))
        && path
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'/' | b'-' | b'_' | b'.'))
}

#[cfg(test)]
mod tests {
    use super::{ReleaseTransport, UpdateError};

    #[test]
    fn signed_grants_cannot_escape_the_configured_https_origin_or_storage_prefix() {
        let transport = ReleaseTransport::new(
            "https://updates.example.org",
            "/api/update-check",
            "/signed/releases/",
        )
        .unwrap();
        let path = "/signed/releases/stable/5.1.0/x86_64-unknown-linux-gnu/manifest.json";
        let grant = format!("https://updates.example.org{path}?token=temporary");
        assert!(transport.storage_url(&grant).is_ok());
        let invalid = [
            format!("http://updates.example.org{path}?token=temporary"),
            format!("https://updates.example.org.evil.invalid{path}?token=temporary"),
            format!("https://user:password@updates.example.org{path}?token=temporary"),
            format!("https://updates.example.org{path}?token=temporary#fragment"),
            format!("https://updates.example.org{path}"),
            format!("https://updates.example.org{path}?grant=temporary"),
            format!("https://updates.example.org{path}?token="),
            format!("https://updates.example.org{path}?token=one&token=two"),
            "https://updates.example.org/untrusted/path?token=owned".into(),
            "https://updates.example.org/signed/releases/../../untrusted/path?token=owned".into(),
            "not-a-url".into(),
        ];
        for grant in invalid {
            assert!(matches!(
                transport.storage_url(&grant),
                Err(UpdateError::Origin)
            ));
        }
    }
}
