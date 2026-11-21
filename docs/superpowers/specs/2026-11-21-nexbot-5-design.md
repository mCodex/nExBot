# nExBot 5.0 em Rust

## Objetivo e ponto de partida

O Rust deve assumir decisões, estado e arbitragem de ações. O OTClient instalado continua sendo o dono das APIs nativas, dos eventos Lua e da interface OTUI. A troca de motor depende de evidência em um cliente real, de paridade dos perfis e da capacidade de voltar para a versão anterior.

A auditoria inicial usa o nExBot `19632d414405e0e9087a11492e39274b14bdfa2d`, SHA do `main` confirmado no GitHub e base de `feat/new_v5`. O fonte do OTClient oficial foi consultado em `dc99b7fae016ed5828d1721173214c5780981ecd`. O executável disponível para os primeiros testes é o TibiaRPGBrasil para macOS arm64. Ele é uma variante, e sua compatibilidade precisa ser medida independentemente do upstream.

## Abordagem

1. **WebSocket em loopback.** Usar o WebSocket de texto para limitar o tamanho antes de decodificar JSON na ponte, com o mesmo transporte nativo de `HTTP.WebSocketJSON`. O código oficial expõe `HTTP` e `json` na sandbox e entrega os callbacks pelo dispatcher. Usar perfil experimental isolado para validar o fluxo antes de alterar a entrada de produção.
2. **HTTP assíncrono em loopback.** Considerar somente se uma variante tiver HTTP funcional e faltar WebSocket. O cliente teria de buscar comandos periodicamente. Medir atraso de polling e custo por sessão antes de aceitar a variante.
3. **Sem IPC suportado.** Classificar a variante como incompatível. Lua permanece limitada às APIs presentes na build.

A opção escolhida para implementação é a primeira. O primeiro comando consulta uma rota curta com a API nativa, com ACK que carrega o resultado observado e NACK para cota, falta de API ou estado inválido. O teste registra posição inicial e movimento observado, com movimento do jogador manual e autorizado em ambiente controlado. A primeira chamada que altera o jogo depende da etapa seguinte e de teste isolado.

## Fluxo da primeira entrega

```text
Bootstrap local -> configuração efêmera -> sandbox Lua
Sandbox Lua      -> hello autenticado -> listener Rust 127.0.0.1
OTClient         -> snapshot + movimento -> sessão Rust
Sessão Rust      -> consulta autorizada -> dispatcher Lua -> g_map.findPath
Sandbox Lua      -> ACK/NACK -> sessão Rust
```

Começar com um pacote Rust para protocolo, sessão e binário. Separar módulos internos por responsabilidade e criar crates independentes conforme dependências e testes ganharem fronteiras reais. Registrar formatos, limites de frames, taxas e buffers como contratos da versão inicial. Medir antes de dividir o runtime em processos adicionais ou trocar a serialização.

O bootstrap cria credencial aleatória efêmera e publica o rendezvous em diretório local com acesso restrito ao usuário. O protocolo autentica ambos os lados antes de trocar eventos ou comandos. A credencial fica fora de URLs, logs e da configuração persistente do bot. Verificar suporte a segredo via arquivo na sandbox e documentar a proteção do diretório no Windows e no POSIX. A ameaça de software local sob o mesmo usuário deve constar no modelo de segurança.

A ponte transmite deltas e um snapshot inicial. Estado de jogo e comandos pertencem à geração da sessão. Comandos expiram, exigem ordem e têm confirmação associada ao ID. Movimento e ataque só liberam a ação quando a observação esperada chega ou o timeout encerra a tentativa. A consulta de rota pode confirmar de imediato porque devolve o valor observado da API. Logout, reload, mudança de andar, perda de link e ressincronização invalidam trabalho incompatível com o novo estado. A ponte usa as rotinas de cleanup da variante verificadas no cliente.

## Navegação, colisões e combate

O planejador Rust usa `g_map.findPath` por consulta nativa limitada. Mede chamadas e duração porque o terceiro argumento do upstream é orçamento de complexidade, e o custo recai na thread do cliente. Os candidatos de combate consideram alcance e linha de visão a partir de cada posição possível. A menor rota de aproximação pode terminar fora da linha de tiro.

A classificação usa terreno, ocupação, visibilidade e transição de andar como observações independentes. `isWalkable(false)` e `isWalkable(true)` ajudam a distinguir uma criatura bloqueando uma célula de terreno intransitável. `hasCreatures()` indica presença e pode incluir criaturas atravessáveis. Tile ausente e orçamento de busca esgotado conservam motivo próprio. Caminho encontrado com criaturas ignoradas diagnostica um bloqueio transitório, com nova observação antes de mover. O planejador nativo pode evitar células com criaturas atravessáveis. A ponte deve reportar a observação do tile separadamente do resultado da rota. A regra de diagonal depende de evidência da variante e do servidor.

CaveBot e TargetBot compartilham o estado de navegação e enviam intenções ao mesmo coordenador. Uma ação de movimento fica pendente por vez. O executor confirma pelo deslocamento observado, com `z` validado em transições. A tentativa expirada invalida a rota e consome orçamento de recuperação. Cura e combate podem progredir em grupos independentes, respeitando recursos e cooldowns compartilhados. Follow mantém alvo a cerca de 1 SQM e reavalia apenas quando eventos ou deadlines mudam o estado relevante.

Os primeiros testes de regressão devem cobrir o fallback nativo que hoje passa flags `0` mesmo em sondagem com `ignoreCreatures`, linha de visão obstruída no primeiro candidato de ataque, criatura passável, mapa parcial, escada, rejeição de passo, confirmação obsoleta e disputa de movimento entre CaveBot, TargetBot e Follow. Rodar replays com a mesma entrada antes de remover executores Lua.

## Configuração, presença e atualização

Importar dados legados em transporte versionado. Manter backup verificável e importer idempotente, com fixtures sanitizadas. Scripts privados e ações `function` podem chamar APIs arbitrárias e dependem de interfaces Lua específicas. Preservar os textos e identificar scripts que exigem substituição ou integração tipada antes do cutover. Cada módulo migrado tem uma autoridade de execução por sessão.

Heartbeat opcional fica em tarefa independente com consentimento explícito, identificadores aleatórios, expiração pelo relógio do servidor e retenção limitada. As Edge Functions validam e limitam ingestão, o Postgres restringe acesso direto e a consulta administrativa retorna agregações. O teste de contagem cobre sessões distintas da mesma instalação. Tratar credenciais copiadas e registros múltiplos como limites da métrica de atividade.

Distribuir executáveis por objeto imutável no Storage, com manifesto Ed25519, bytes canônicos, chave identificada, validade temporal e proteção contra downgrade. URL assinada tem função de acesso e a assinatura de software tem função de autenticidade. O atualizador grava e valida por streaming, usa instalação atômica compatível com o SO, mantém a versão anterior e exige handshake do novo processo para confirmar a atualização. A chave privada fica no processo de publicação protegido. O backend suspende entregas por canal sem emitir comandos para instalações.

## Sequência de validação

- Fase A confirma checkout, sandbox, riscos, inventário e baseline. Os 271 testes Lua aprovados fornecem uma base funcional local. A latência e o frame time atuais precisam ser medidos no cliente em sessões comparáveis.
- Fase B usa RED → GREEN → REFACTOR para falhas do protocolo, autenticação, geração, expiração e ACK. O smoke real prova handshake, snapshot, movimento observado e resposta nativa sem recompilar.
- Fase C porta regras por domínio, confirma paridade e usa o perfil isolado para preservar rollback. Cada entrega inclui testes da regra e do executor que passam pelo caso real de entrada.
- Fases D e E validam Supabase, retenção, RLS, storage, assinatura, rollback e interrupções. A publicação de teste usa staging.
- Fase F exige cobertura de linhas e branches conforme o prompt, relatórios por crate, matriz Windows/Linux, replays, operações reais e comparação de perfil de release. Nenhuma variante recebe selo de suporte com base apenas em mocks.

O [registro da auditoria](../../adr/0001-rust-discovery.md) reúne evidências, inventário inicial e lacunas. O [modelo de ameaças](../../SECURITY.md) registra as fronteiras para a implementação.
