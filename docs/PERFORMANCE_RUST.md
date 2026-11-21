# Desempenho da prévia Rust

## Referência vBot 4.8

A inspeção foi feita no OTClient oficial `dc99b7fae016ed5828d1721173214c5780981ecd`. O CaveBot usa macro nominal de 20 ms, conserva um cursor e pode manter três passos pendentes. O TargetBot reavalia a cada 100 ms, reduz o raio de seis para três acima de dez monstros e faz consultas de rota durante a varredura. A posição pode ser publicada no prewalk. [CaveBot](https://github.com/opentibiabr/otclient/blob/dc99b7fae016ed5828d1721173214c5780981ecd/mods/game_bot/default_configs/vBot_4.8/cavebot/cavebot.lua), [cursor](https://github.com/opentibiabr/otclient/blob/dc99b7fae016ed5828d1721173214c5780981ecd/mods/game_bot/default_configs/vBot_4.8/cavebot/walking.lua), [TargetBot](https://github.com/opentibiabr/otclient/blob/dc99b7fae016ed5828d1721173214c5780981ecd/mods/game_bot/default_configs/vBot_4.8/targetbot/target.lua), [prewalk](https://github.com/opentibiabr/otclient/blob/dc99b7fae016ed5828d1721173214c5780981ecd/src/client/localplayer.cpp#L81)

A prévia conserva o cursor em Rust e consulta a rota nativa quando um evento relevante exige novo cálculo. Há no máximo uma consulta pendente na sessão. O fixture injeta 10.000 mudanças fora da rota e exige zero consultas adicionais. Outros fixtures forçam colisão transitória, desvio, mudança de andar e resposta antiga. Esse resultado descreve o número de decisões no fixture, sem representar a carga de uma sessão jogável.

## Comparação de perfis

Medição em macOS arm64 com Rust 1.100.0. Cada perfil teve cinco execuções de aquecimento e 50 medições de `nexbot-engine --version`, incluindo a criação do processo. O RSS de pico vem de uma execução separada de `/usr/bin/time -l`. O gzip usa nível 9 e timestamp fixado em zero.

| Perfil | Binário | gzip | RSS máximo | p50 | p95 | p99 |
|---|---:|---:|---:|---:|---:|---:|
| Release `z` + fat LTO | 453.472 B | 226.952 B | 1.671.168 B | 3,355 ms | 3,848 ms | 4,110 ms |
| Balanced `3` + thin LTO | 700.512 B | 314.390 B | 1.720.320 B | 3,332 ms | 10,188 ms | 13,409 ms |

O executável menor foi usado nas builds de teste. CPU e latência em jogo ainda precisam de medição para selecionar o perfil de produção.

```sh
cd rust
cargo build --locked --release -p nexbot-engine
cargo build --locked --profile balanced -p nexbot-engine
wc -c target/{release,balanced}/nexbot-engine
gzip -n -9 -c target/release/nexbot-engine | wc -c
gzip -n -9 -c target/balanced/nexbot-engine | wc -c
/usr/bin/time -l target/release/nexbot-engine --version
/usr/bin/time -l target/balanced/nexbot-engine --version
cargo test --locked -p nexbot-engine --test route
```

## Comparação no cliente

Use a mesma build de OTClient, servidor, sessão, mapa, rota e perfil entre os ensaios. Registre RTT de IPC e tempo de decisão fora de frame, CPU/RSS, tempo de frame, consultas de pathfinding, rejeições e retransmissões. Separe posição prevista, posição observada e aceitação pelo servidor. Cubra passagem estreita, criatura atravessável, mudança de andar, rota parcialmente visível e linha de tiro obstruída. Esses ensaios e o baseline comparável de vBot continuam pendentes. O atualizador tem perfil e binário separados dos números acima.
