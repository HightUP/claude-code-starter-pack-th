---
name: security-check
description: Auditoria de segurança Security by Design. Use quando o usuário pedir "audite a segurança", "security review", "verifique vulnerabilidades", ou antes de subir feature pra produção. Cobre OWASP Top 10, gestão de secrets, AuthN/AuthZ, supply chain e logs.
allowed-tools: Read, Grep, Glob, Bash
---

# Security Check — Security by Design

Auditoria pragmática de segurança. Evita teatro: foca em ameaças reais para a stack
do projeto. Os exemplos abaixo usam Python/Flask, Next.js/TS, GCP/Cloudflare/Supabase,
mas os princípios se aplicam a qualquer stack (inclusive PHP/MySQL) — adapte o exemplo
técnico ao que o projeto realmente usa, sem pular o item.

## Modo de operação

1. Comece perguntando (ou inferindo) o **superfície de ataque**: API pública? Login? Pagamentos? Upload?
2. Rode o checklist priorizado (ameaças mais prováveis primeiro).
3. Classifique findings como **CRÍTICO** (bloqueia deploy), **ALTO**, **MÉDIO**, **INFO**.
4. Para cada finding: descreva ameaça → impacto → fix concreto.

## Checklist priorizado

### 🔥 CRÍTICO — sempre verificar

**Secrets management**
- [ ] Nenhum secret hardcoded (grep por `api_key`, `password`, `secret`, `token` em código).
- [ ] `.env` no `.gitignore` e nunca commitado (`git log --all --full-history -- .env`).
- [ ] Secrets em runtime vêm de Secret Manager / env vars, ou — em stacks sem esse recurso (ex: PHP em hospedagem compartilhada) — de um arquivo de configuração em código (`config/config.php`) fora da pasta pública, git-ignored, nunca de `.env` exposto por engano.
- [ ] **Dockerfile sem `ARG`/`ENV` para secret.** Qualquer `ARG`/`ENV` fica gravado permanentemente nas camadas da imagem (`docker history`/`docker inspect`), mesmo que o valor "não seja usado" de fato no build — é um vazamento independente do git (dois artefatos diferentes: histórico do repo vs. imagem construída). Isso vale mesmo quando a env var já está configurada corretamente em runtime no painel/orquestrador (Coolify, EasyPanel, Railway, k8s): muitas PaaS repassam **toda** variável do painel como `--build-arg` pra qualquer `ARG` de mesmo nome no `Dockerfile`, sem avisar. Fix: ler segredo só via `process.env`/`os.environ` já no container rodando; se o build precisar de credencial (ex: registry privado, `.npmrc`), usar `RUN --mount=type=secret` (BuildKit) — nunca `ARG`/`ENV`. Exceção: variáveis públicas por design (`NEXT_PUBLIC_*`, embutidas no bundle do browser mesmo).
- [ ] Rotação documentada para secrets de produção.

**Injeção (SQLi, XSS, Command Injection)**
- [ ] Queries SQL parametrizadas (`?` ou named params), nunca f-string/template literal.
- [ ] User input nunca concatenado em comandos shell (`subprocess` com lista, não string).
- [ ] React/Next renderizando user content com escape automático (sem `dangerouslySetInnerHTML` sem sanitização).
- [ ] Headers `Content-Type` e `X-Content-Type-Options: nosniff` em respostas.

**AuthN/AuthZ**
- [ ] Toda rota não-pública tem middleware de auth aplicado.
- [ ] Authorization checa permissão *do recurso específico*, não só "está logado".
- [ ] JWT com expiração curta + refresh token; assinatura verificada com chave pública/HMAC server-side.
- [ ] Senhas com bcrypt/argon2 (cost ≥ 12), nunca MD5/SHA1.
- [ ] MFA disponível para contas privilegiadas.

### 🟠 ALTO

**Inputs e validação**
- [ ] Schema validation na borda (Pydantic, Zod) — incluindo tamanho máximo de strings/arrays.
- [ ] Rate limiting em endpoints sensíveis (login, signup, password reset).
- [ ] CSRF tokens em forms server-rendered (ou SameSite=Strict cookies).
- [ ] CORS configurado restritivamente (não `*` em prod).

**Sessões e cookies**
- [ ] Cookies de sessão: `HttpOnly`, `Secure`, `SameSite=Lax/Strict`.
- [ ] Logout invalida sessão server-side (não só apaga cookie).
- [ ] Session fixation: novo session ID após login.
- [ ] **Timeout por inatividade**, não só validade máxima do token. Client SDK com auto-refresh (Supabase, Firebase) mantém a sessão viva pra sempre enquanto a aba ficar aberta, mesmo sem nenhuma interação do usuário — isso não é "sessão expira", é sessão eterna disfarçada. Se o sistema movimenta dinheiro real ou dado sensível, implemente logout automático client-side por inatividade (ex: 15min sem mousemove/keydown/click, com aviso antes de deslogar).

**Webhooks / callbacks de integração externa (Stripe, bancos, PIX, gateways de pagamento)**
- [ ] Toda rota de webhook valida a origem antes de processar o payload — assinatura HMAC (`X-Signature`/`Stripe-Signature`), mTLS dedicado, ou no mínimo um secret fixo (query string ou header) comparado com `timingSafeEqual`/`hmac.compare_digest` (nunca `===`/`==`, que vaza timing). Rota sem nenhuma verificação de origem é um endpoint público que aceita "confia em mim" de qualquer um na internet.
- [ ] O handler nunca muda estado (aprovar pagamento, liberar produto, confirmar pedido) só com base no payload cru recebido — sempre reconfirma via chamada autenticada de volta pro provedor (`GET /pagamento/{id}`) antes de gravar. Isso neutraliza o pior cenário (forjar aprovação) mesmo se a validação de origem falhar ou for mais fraca (ex: secret em vez de mTLS).
- [ ] Reentrega/duplicidade tratada (provedor reenvia o mesmo evento) — idempotência por ID do evento/transação, não por "já rodou uma vez nesse processo".
- [ ] Falha ao processar um item do lote não derruba os outros itens do mesmo callback.

**File upload / Storage**
- [ ] Whitelist de tipos MIME (verificada no servidor, não só no cliente).
- [ ] Tipo real do arquivo validado (magic bytes/assinatura), não só a extensão ou o MIME declarado pelo cliente.
- [ ] Tamanho máximo enforced.
- [ ] Nome do arquivo normalizado/sanitizado (evita path traversal e sobrescrita de arquivo crítico).
- [ ] Arquivos servidos de domínio separado ou com `Content-Disposition: attachment`.
- [ ] Não executa nada do que foi uploaded.

### 🟡 MÉDIO

**Supply chain**
- [ ] Lockfiles commitados (`package-lock.json`, `pnpm-lock.yaml`, `requirements.lock`).
- [ ] Dependências auditadas (`npm audit`, `pip-audit`) — sem CVE crítica/alta.
- [ ] Dependabot/Renovate ativo.

**Logs e observabilidade**
- [ ] Logs **não** contêm: tokens, senhas, PII completa, payment info.
- [ ] Eventos de segurança logados: login fail, permission denied, password change.
- [ ] Logs estruturados (JSON) com correlation ID.
- [ ] Se o log de erro é gravado em banco de dados, existe contingência em arquivo para quando o banco estiver indisponível, a conexão falhar, ou o próprio erro impedir o registro normal — arquivo fora da pasta pública, protegido contra acesso direto pela web.

**Infra (GCP/Cloudflare)**
- [ ] Cloud Run/Functions com IAM mínimo (não Editor/Owner).
- [ ] Cloud SQL com IP privado, não público.
- [ ] WAF (Cloudflare) ativo nas APIs públicas.
- [ ] HTTPS enforced (redirect 301 de HTTP).

**Container / Docker**
- [ ] Stage final (`runner`) do `Dockerfile` roda com `USER` não-root — imagens `-alpine` (node, python) já trazem um usuário sem privilégio pronto (`node`, uid 1000), só falta `COPY --chown=` nos arquivos copiados + `USER <nome>` antes do `CMD`. Container root com uma RCE na aplicação (dependência vulnerável, upload malicioso) vira root **no container** de graça — não escapa o container sozinho, mas remove uma camada de contenção de graça.
- [ ] Nenhum secret via `ARG`/`ENV` no `Dockerfile` (ver item em Secrets management, CRÍTICO).
- [ ] `.dockerignore` exclui `.env*`, certificados/chaves, `node_modules`, `.git` — evita que `COPY . .` (ou `COPY web/ ./` sem escopo) inclua secret local sem querer.
- [ ] Imagem final não carrega ferramenta de build desnecessária (multi-stage: `deps`/`builder` separados do `runner`, só o output necessário copiado pro stage final).

**Banco de dados (Supabase/Postgres)**
- [ ] RLS habilitado em toda tabela com dado sensível, **com política real** (RLS ligado sem policy bloqueia tudo; sem RLS libera tudo pro `anon`/`authenticated`) — checar via `pg_class.relrowsecurity` + `pg_policies`, não só assumir pelo nome da migration.
- [ ] Se o projeto Supabase é compartilhado com outros apps/clientes (schemas diferentes no mesmo banco), a policy não pode confiar só em `authenticated` — precisa checar se o usuário tem vínculo *com este app específico* (ex: existe linha dele numa tabela de usuários deste schema), senão qualquer autenticado de qualquer app do mesmo projeto acessa dado de outro.
- [ ] Função `SECURITY DEFINER` exposta via RPC: confirmar que ela só responde sobre o próprio `auth.uid()` do chamador (nunca aceita um ID arbitrário de outro usuário sem checar permissão) e que tem `SET search_path` fixo.
- [ ] "Leaked Password Protection" do Supabase Auth habilitada (Dashboard → Authentication → Policies) — bloqueia senha já vazada em base pública (HaveIBeenPwned).

### 🔵 INFO

- [ ] Header `Strict-Transport-Security` (HSTS) em domínios de produção.
- [ ] Header `X-Frame-Options: DENY` (ou `frame-ancestors` na CSP) — evita clickjacking.
- [ ] Header `Referrer-Policy` (ex: `strict-origin-when-cross-origin`) — evita vazar URL completa (com token/ID em query string) pro `Referer` de terceiros.
- [ ] Header `Content-Security-Policy` mesmo que permissivo no início.
- [ ] `robots.txt` e `security.txt` configurados.
- [ ] Mensagens de erro genéricas para o usuário, detalhe só nos logs internos.

## Output esperado

```markdown
## Security Audit — <projeto/feature>

### Resumo executivo
- Findings críticos: N
- Findings altos: N
- Findings médios: N
- Status: ✅ OK PRA DEPLOY | ⚠️ DEPLOY COM RESSALVAS | 🛑 NÃO FAZER DEPLOY

### Findings

#### 🔥 CRÍTICO-01: <título curto>
**Onde:** `path/file.py:42`
**Ameaça:** <atacante consegue X>
**Impacto:** <dano concreto: vazamento de Y, escalada de privilégio, etc>
**Fix:**
```python
# antes
query = f"SELECT * FROM users WHERE id = {user_id}"
# depois
query = "SELECT * FROM users WHERE id = %s"
cursor.execute(query, (user_id,))
```

(repetir por finding)

### Próximos passos
1. <ação imediata>
2. <ação backlog>
```

Se essa auditoria for pré-requisito de um commit bloqueado por
`pre-commit-security-gate.sh` (arquivo sensível staged), inclua ao final da
mensagem de commit uma das linhas:
- `Security-check: ok (sem findings críticos)` — nenhum CRÍTICO/ALTO achado.
- `Security-check: findings corrigidos (resumo curto)` — achou e já corrigiu antes de commitar.

Não adicione a linha só pra "destravar" o commit sem ter revisado de verdade —
o hook confia na marca, então ela só vale alguma coisa se a revisão aconteceu.

## O que NÃO fazer

- Não recomende solução genérica ("use HTTPS") — verifique se já está aplicada.
- Não infle severidade. CRÍTICO é o que **realmente bloqueia deploy**.
- Não duplique o que SAST/DAST tools já pegariam — foque em logic flaws e config.
- Não pergunte demais antes de começar. Faça a varredura inicial e refine depois.
