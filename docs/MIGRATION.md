# Migração nExBot para Rust

## Perfil de diagnóstico

Em um ambiente autorizado, crie um perfil de bot separado e copie para ele apenas `bridge/_Loader.lua`. Use um diretório do próprio usuário e guarde o perfil Lua atual com seus arquivos de configuração.

Compile com `cargo build --manifest-path rust/Cargo.toml --locked --release -p nexbot-engine`. Execute `nexbot-engine diagnose <caminho-do-perfil>/rust-session` e carregue o perfil de diagnóstico no cliente. No Windows, use `nexbot-engine.exe`. O engine aguarda por até 90 segundos pela primeira conexão.

A interface mostra o estado da conexão. O terminal registra autenticação e o código da consulta nativa de rota. Provoque um movimento manual em local seguro para observar os deltas. Para experimentar a rota, inicie outra sessão com `nexbot-engine preview <caminho-do-perfil>/rust-session X Y Z` e use um destino visível até 32 SQM no mesmo andar. Caminhe manualmente. O terminal mostra o próximo tile, a chegada e bloqueios observados. Em caso de falha, feche o perfil experimental e selecione o anterior no cliente. Se um encerramento abrupto deixar um arquivo de rendezvous, confirme que o processo anterior saiu antes de removê-lo e iniciar outro.

## Paridade da entrega

| Área | Origem no perfil atual | Estado em Rust |
|---|---|---|
| Sessão | ACL, EventBus, UnifiedTick | Diagnóstico de WebSocket e estado de sessão testados com cliente simulado. |
| CaveBot | `cavebot/*.lua`, `cavebot_configs/*.cfg` | Prévia com caminho nativo, cursor, desvio e observação de colisão. Waypoints, ações, transições automatizadas, import e execução pendentes. |
| TargetBot | `targetbot/*.lua`, `targetbot_configs/*.json` | Seleção de posição de tiro com testes. Máquina de combate e confirmação de ataque pendentes. |
| Follow | `core/follow.lua`, armazenamento de perfil | Cálculo da distância no mesmo andar com testes. Recaptura, rastreamento e execução pendentes. |
| AttackBot, HealBot e buffs | `core/attack/`, `core/heal/`, `nExBot_configs/profile_*/` | Pendente. |
| Inventário, quiver, loot e equipment | `core/containers/`, `targetbot/looting.lua`, perfis e supplies | Pendente. |
| Insights, analyzer e extras | `targetbot/monster_*.lua`, `core/analyzer.lua`, `core/extras.lua`, preferências locais | Pendente. |
| OTUI e scripts privados | `*.otui`, `private/`, ações `function` | Status do diagnóstico disponível. Migração dos scripts depende de inventário e fixtures. |

O commit de colisões corrige o perfil Lua atual. O diagnóstico Rust segue em perfil separado até haver evidência de compatibilidade. A validação do import precisa de fixtures sanitizadas e backups em local separado. Nenhum import ou cutover foi executado nesta etapa.
