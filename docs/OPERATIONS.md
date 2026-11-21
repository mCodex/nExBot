# Operação dos binários nExBot

## Diagnóstico local

O engine aceita `--version`, `diagnose PERFIL/rust-session` e `preview PERFIL/rust-session X Y Z`. Execute em diretório de perfil reservado ao usuário. A [migração](MIGRATION.md) descreve o carregamento isolado da ponte e o retorno ao bot Lua.

## Publicação e verificação

O CLI offline `release-publisher sign KEY_SEED_FILE METADATA_JSON ARTIFACT OUTPUT_DIR` verifica tamanho, SHA-256 e cabeçalho do binário, então grava o manifesto canônico e a assinatura Ed25519 em um diretório existente. Use um arquivo bruto de chave de 32 bytes acessível apenas ao assinante. Use uma chave de teste dedicada para ensaios.

O manifesto vincula o target, a versão, o canal, a janela de validade, o artefato e a compatibilidade do engine e da ponte. Os bytes assinados devem ser publicados sem reserialização. Distribua os objetos com nomes imutáveis e ative a entrega somente depois de verificar os objetos publicados.

## Instalação

```text
nexbot-bootstrap --version
nexbot-bootstrap check STORE SETTINGS
nexbot-bootstrap status STORE SETTINGS
nexbot-bootstrap update STORE SETTINGS PERFIL/rust-session
nexbot-bootstrap active-path STORE SETTINGS
nexbot-bootstrap rollback STORE SETTINGS
```

Use uma pasta local restrita para `STORE` e um arquivo JSON local para `SETTINGS`. Os campos incluem `service_url`, `check_path`, `signed_objects_prefix`, `channel`, `baseline_engine_version`, `bridge_version`, `protocol_version`, `rollout_id` UUIDv7 e `trusted_keys`. Cada chave pública tem `id`, `public_key_hex` e `revoked`. Os valores de confiança são provisionados localmente. A build de teste está sem âncoras de produção.

Faça a atualização entre sessões. O bootstrap mantém slots distintos, verifica a assinatura e o executável antes de qualificar o candidato, e só muda a versão ativa depois de receber `nexbot-ipc-health-v1`. Durante o health check, carregue o perfil de diagnóstico no cliente. O prazo atual é de 60 s. Depois da qualificação, o bootstrap termina o candidato de teste. Um launcher externo usa `active-path` para escolher o slot ou o binário de base quando o comando imprime uma linha vazia.

## Incidente e reversão

Suspenda a distribuição no serviço de publicação se houver corrupção, incompatibilidade ou comprometimento de chave. A troca de chaves de confiança exige provisionamento local que preserve a integridade do arquivo de configurações. O rollback local restaura o slot anterior ou a base empacotada e conserva o piso de versão aceito. Confira `status` e a versão de `active-path` antes de iniciar a próxima sessão.

A recuperação foi exercitada com falhas injetadas em macOS arm64. O ensaio conectado, o bootstrap nativo em Windows e Linux e a publicação remota permanecem pendentes.
