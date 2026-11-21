# Segurança do nExBot 5.0

Modelo inicial para revisão do desenho. Os controles abaixo são critérios para a implementação e ainda precisam de teste.

## Fronteiras

- No computador do jogador, o bootstrap, o processo Rust e o perfil Lua compartilham o contexto do usuário. O segredo efêmero protege o canal contra outros clientes locais sem acesso ao rendezvous. Um processo que roda com o mesmo usuário pode ter acesso ao diretório local. Logs e perfil persistente devem omitir a credencial.
- O cliente afirma o estado visível de jogo. O engine aceita apenas tipos, comprimentos, sequência e geração válidos. A ponte executa um conjunto fixo de ações com precondições conferidas no cliente.
- As funções de telemetria recebem dados não confiáveis. A chave de serviço e a administração permanecem no ambiente Supabase. O engine local segue operando se a telemetria falhar.
- A publicação separa armazenamento, ativação do release e chave do assinante. O canal de distribuição controla acesso e disponibilidade. A chave pública confiável, a versão e o hash validam a identidade do artefato.

## STRIDE

| Ameaça | Controle previsto | Evidência esperada |
|---|---|---|
| Identidade falsa no IPC | Bind em loopback, credencial efêmera, autenticação mútua com nonces e associação a sessão e versão | Conexão sem credencial, replay de handshake, cliente errado, listener em endereço inesperado |
| Alteração de evento ou comando | Campos tipados, limites de mensagem, geração e sequência, precondições locais e cancelamento | Mensagem gigante, bytes inválidos, duplicação, expiração, mudança de andar entre decisão e execução |
| Negação de ação executada | ACK/NACK correlacionado com ID e observação do cliente, registro local sem segredos | Chamada aceita sem efeito, ACK antigo, resultado recebido após timeout |
| Exposição de dados | Eventos de jogo locais; telemetria com consentimento e esquema mínimo; RLS e RPC restritas; métricas administrativas agregadas | Papéis `anon`, `authenticated` e admin; nenhum nome de personagem, conta, chat, posição ou caminho no payload remoto |
| Drenagem de recursos | Limites de fila, taxa e tempo; coalescência por classe; snapshot de resync se perder evento crítico; quotas no ingresso | Bursts, timeout, disconnect, fila cheia, 429, usuário offline |
| Elevação via Lua ou Edge | Dispatcher com operações explícitas, credencial de sessão no ingresso, privilégio mínimo na execução do banco | Argumento extra, chamada arbitrária, tentativa de relatório admin com credencial de sessão |
| Publisher ou Storage comprometido | Assinatura Ed25519 independente da URL, artefatos imutáveis, manifestos limitados por canal, plataforma e tempo, proteção contra downgrade | Artefato trocado, chave desconhecida ou revogada, manifesto antigo, assinatura inválida, release incompleto |
| Anulação da instalação | Staging no mesmo volume, verificação antes do swap, versão anterior recuperável e journal, health check por handshake | Arquivo bloqueado no Windows, crash entre fases, falta de espaço, symlink e falha no handshake |

## Chaves e revogação

Após definir o primeiro assinante, gravar a chave pública inicial no atualizador e sua identificação no manifesto. A rotação depende de uma atualização confiável de âncoras ou da reinstalação por distribuição confiável quando a chave anterior for comprometida. Revogar o material comprometido, suspender novas entregas no backend e publicar a sequência de recuperação. Chave de assinatura e credenciais de publicação têm ciclos de revogação independentes. A suspensão no backend interrompe a distribuição.

A regra de rollback deve distinguir restaurar o próprio binário anterior, já verificado e mantido durante uma atualização incompleta, de instalar um release remoto com versão inferior. O segundo caso exige autorização assinada e específico escopo de canal e versão.

## Acesso remoto

Armazenar heartbeat por sessão com expiração pelo relógio do Postgres. O acesso direto por papéis de cliente deve ficar restrito nas tabelas de sessão, instalação, publicação e artefatos. A função administrativa usa autorização verificável e devolve apenas agregações. IDs aleatórios e credenciais copiáveis permitem estimativa de atividade, com risco de registros artificiais.

Os testes devem usar ambiente local ou staging isolado, sem segredos de produção disponíveis a PRs. A revisão de controles usa [OWASP ASVS](https://owasp.org/www-project-application-security-verification-standard/), [Supabase Edge Function Auth](https://supabase.com/docs/guides/functions/auth), [Storage RLS](https://supabase.com/docs/guides/storage/security/access-control) e [SLSA](https://slsa.dev/).
