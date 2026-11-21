use std::{
    fs,
    path::PathBuf,
    process::{Child, Command},
    thread,
    time::{Duration, Instant},
};

use serde_json::{Value, json};
use tungstenite::{Message, client::IntoClientRequest, connect};

fn spawn(suffix: &str, goal: Option<[&str; 3]>) -> (Child, PathBuf, String, String, String) {
    let path = std::env::temp_dir().join(format!(
        "nexbot-probe-{}-{suffix}.session",
        std::process::id()
    ));
    let mut command = Command::new(env!("CARGO_BIN_EXE_nexbot-engine"));
    command
        .arg(if goal.is_some() {
            "preview"
        } else {
            "diagnose"
        })
        .arg(&path);
    if let Some(goal) = goal {
        command.args(goal);
    }
    let mut engine = command
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .unwrap();

    let deadline = Instant::now() + Duration::from_secs(5);
    let rendezvous = loop {
        if let Ok(contents) = fs::read_to_string(&path)
            && contents.ends_with('\n')
            && contents.lines().count() == 3
        {
            break contents;
        }
        if Instant::now() >= deadline {
            let _ = engine.kill();
            let _ = engine.wait();
            panic!("engine did not publish rendezvous");
        }
        thread::sleep(Duration::from_millis(10));
    };

    assert_eq!(rendezvous.lines().count(), 3);
    let mut lines = rendezvous.lines();
    let port = lines.next().unwrap();
    let token = lines.next().unwrap();
    let proof = lines.next().unwrap();
    (
        engine,
        path,
        format!("ws://127.0.0.1:{port}/"),
        token.to_owned(),
        proof.to_owned(),
    )
}

#[test]
fn engine_accepts_only_the_rendezvous_and_completes_a_native_probe_reply() {
    let (engine, path, endpoint, token, proof) = spawn("probe", None);
    let (mut client, _) = connect(endpoint).unwrap();
    let version = env!("CARGO_PKG_VERSION");

    client.send(Message::text(json!({
        "type": "hello", "protocol": 1, "bridge_version": version, "path_probe": true, "token": token
    }).to_string())).unwrap();
    client.send(Message::Ping(Vec::new().into())).unwrap();
    let ready: Value = serde_json::from_str(client.read().unwrap().to_text().unwrap()).unwrap();
    assert_eq!(
        ready,
        json!({"type": "ready", "proof": proof, "protocol": 1})
    );

    assert!(matches!(client.read().unwrap(), Message::Pong(_)));

    client
        .send(Message::text(
            json!({
                "type": "snapshot", "sequence": 1, "position": {"x": 60, "y": 100, "z": 7}
            })
            .to_string(),
        ))
        .unwrap();
    let probe: Value = serde_json::from_str(client.read().unwrap().to_text().unwrap()).unwrap();
    assert_eq!(probe["destination"], json!({"x": 61, "y": 100, "z": 7}));
    client
        .send(Message::text(
            r#"{"type":"ack","sequence":2,"id":1,"path_result":0}"#,
        ))
        .unwrap();
    client
        .send(Message::text(
            r#"{"type":"move","sequence":3,"position":{"x":61,"y":100,"z":7}}"#,
        ))
        .unwrap();
    client.close(None).unwrap();

    let output = engine.wait_with_output().unwrap();
    assert!(output.status.success());
    assert!(
        String::from_utf8(output.stdout)
            .unwrap()
            .lines()
            .any(|line| line == "nexbot-ipc-health-v1")
    );
    assert!(!path.exists());
}

#[test]
fn rejects_browser_origins_and_consumes_invalid_handshakes() {
    let (engine, path, endpoint, _, _) = spawn("origin", None);
    let mut request = endpoint.into_client_request().unwrap();
    request
        .headers_mut()
        .insert("origin", "https://example.com".parse().unwrap());
    assert!(connect(request).is_err());
    assert!(!engine.wait_with_output().unwrap().status.success());
    assert!(!path.exists());
}

#[test]
fn rejects_invalid_text_without_echoing_the_payload() {
    let (engine, path, endpoint, _, _) = spawn("bad-frame", None);
    let (mut client, _) = connect(endpoint).unwrap();
    client
        .send(Message::text("sentinel-secret-that-must-not-be-echoed"))
        .unwrap();
    let outcome = engine.wait_with_output().unwrap();
    assert!(!outcome.status.success());
    assert!(
        !String::from_utf8(outcome.stderr)
            .unwrap()
            .contains("sentinel-secret")
    );
    assert!(!path.exists());
}

#[test]
fn version_and_usage_have_distinct_exit_status() {
    let mut cli = Command::new(env!("CARGO_BIN_EXE_nexbot-engine"));
    let version = cli.arg("--version").output().unwrap();
    assert!(version.status.success());
    assert!(
        String::from_utf8(version.stdout)
            .unwrap()
            .contains(env!("CARGO_PKG_VERSION"))
    );

    let usage = Command::new(env!("CARGO_BIN_EXE_nexbot-engine"))
        .arg("--unknown")
        .output()
        .unwrap();
    assert!(!usage.status.success());
    assert!(String::from_utf8(usage.stderr).unwrap().contains("usage"));
}

#[test]
fn preview_process_reuses_the_native_route_and_reports_a_blocked_step() {
    let (engine, path, endpoint, token, _) = spawn("route", Some(["62", "100", "7"]));
    let (mut client, _) = connect(endpoint).unwrap();
    client.send(Message::text(json!({
        "type": "hello", "protocol": 1, "bridge_version": env!("CARGO_PKG_VERSION"), "path_probe": true, "token": token
    }).to_string())).unwrap();
    assert!(client.read().unwrap().is_text());

    client
        .send(Message::text(
            r#"{"type":"snapshot","sequence":1,"position":{"x":60,"y":100,"z":7}}"#,
        ))
        .unwrap();
    let probe: Value = serde_json::from_str(client.read().unwrap().to_text().unwrap()).unwrap();
    assert_eq!(probe["type"], "route_probe");
    assert_eq!(probe["destination"], json!({"x": 62, "y": 100, "z": 7}));
    client
        .send(Message::text(
            r#"{"type":"route_ack","sequence":2,"id":1,"directions":[1,1]}"#,
        ))
        .unwrap();

    let watch: Value = serde_json::from_str(client.read().unwrap().to_text().unwrap()).unwrap();
    assert_eq!(
        watch,
        json!({"type": "watch_tile", "position": {"x":61,"y":100,"z":7}})
    );
    client.send(Message::text(r#"{"type":"tile","sequence":3,"position":{"x":61,"y":100,"z":7},"walkable":false,"ignore_creatures":true}"#)).unwrap();
    client.close(None).unwrap();

    let output = engine.wait_with_output().unwrap();
    assert!(output.status.success());
    let logs = String::from_utf8(output.stdout).unwrap();
    assert!(logs.contains("preview next tile 61,100,7"));
    assert!(logs.contains("preview route unavailable"));
    assert!(!logs.contains("nexbot-ipc-health-v1"));
    assert!(!path.exists());
}
