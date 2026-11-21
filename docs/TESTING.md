# Testes Rust e Lua

## Resultado local

| Verificação | Evidência |
|---|---|
| `make test` | 286 testes Lua aprovados. |
| `luajit -b bridge/_Loader.lua /tmp/nexbot-bridge.luac` | Sintaxe da ponte validada. |
| `cargo test --locked --workspace` | 36 testes Rust aprovados em macOS arm64, incluindo processos e WebSocket em loopback. |
| `cargo fmt --all --check` e `cargo clippy --locked --workspace --all-targets -- -D warnings` | Aprovados localmente. |
| `cargo audit --file rust/Cargo.lock` | Aprovado com RustSec carregado e 183 dependências travadas. |
| Cliente real | Pendente. Os testes Lua substituem as APIs do jogo e os testes de socket usam cliente sintético. |
| Release nativo | Build macOS arm64 executada localmente. Binários macOS Intel, Linux x64 e Windows x64 GNU compilados, com execução nessas plataformas pendente. O target Windows x64 MSVC passou no `cargo check`. |
| CI | Matriz preparada para os quatro runners. Execução remota pendente. |

A inspeção confirmou como fontes principais Tungstenite 0.30.0, Serde 1.0.229, serde_json 1.0.154 e getrandom 0.4.3 para o engine. O atualizador usa Ed25519 Dalek 3.0.0, Reqwest 0.13.5 com Rustls, sha2 0.11.1 e semver 1.0.28. A resolução está no lockfile. O build usa Rust 1.100.0. Nightly é reservado para instrumentação de branches.

## Cobertura obrigatória

Medição local com `cargo-llvm-cov 0.9.2` e LLVM 23.1.6. O critério de 90% permanece bloqueante.

| Pacote | Linhas | Branches |
|---|---:|---:|
| Workspace | 82,27% | 71,00% |
| `nexbot-engine` | 94,03% | 78,08% |
| `nexbot-updater` | 74,91% | 67,47% |

```sh
cd rust
cargo +nightly-2026-11-19 llvm-cov --locked --workspace --branch --no-report
cargo +nightly-2026-11-19 llvm-cov report --branch --lcov --output-path lcov.info
cargo +nightly-2026-11-19 llvm-cov report --branch --html
cargo +nightly-2026-11-19 llvm-cov report --branch --fail-under-lines 90
python3 ../tools/check-rust-coverage.py lcov.info --branches
```

O gate por pacote lê os registros de produção sob `src/`. A sequência de regressão cobre autenticação, frame inválido, rejeição de browser, sequência, deadline, colisão, route cursor, versão/assinatura/compatibilidade, diretórios inseguros, rollback e recuperação local. Faltam E2E no OTClient conectado, testes nativos multiplataforma do bootstrap, ensaios de stress e fuzzing, paridade funcional e a publicação de staging.
