# STATUS

Última atualização: 2026-08-27

## O que já foi feito

- Pipeline de segurança estática configurada: hooks (`pre-commit-security-gate.sh`,
  `pre-commit-secrets.sh`, `pre-bash-guard.sh`, `security-topic-reminder.sh`), skills
  `security-check` e `web-app-checklist`, plugin `claude-security`.
- Avaliado o repositório `usestrix/strix` (AI pentesting agent) como possível adição.
  Conclusão: complementar (dinâmico/exploit real) às skills estáticas já existentes,
  não redundante.
- Instaladas via `npx skills add usestrix/strix` as 9 skills oficiais da Strix em
  `.agents/skills/` (symlinked pro Claude Code): `penetration-testing-with-strix`,
  `web-app-penetration-testing`, `api-security-testing`, `owasp-top-10-testing`,
  `find-security-vulnerabilities-in-code`, `application-security-testing`,
  `ci-security-scanning-with-strix`, `fix-security-vulnerabilities-with-strix`,
  `managed-pentesting-with-strix`.
- Guardrails documentados no `CLAUDE.md` (seção "Pentest dinâmico real com Strix"):
  nunca invocar essas skills automaticamente, sempre confirmar autorização do alvo
  e ambiente antes de rodar.
- Binário `strix` instalado via `pip install --user strix-agent` (v1.5.3) — usado
  `pip` em vez do script `curl | bash` do site oficial pra evitar a regra `deny`
  (`curl * | sh`) do `.claude/settings.json`. Executável em
  `C:\Users\thali\AppData\Roaming\Python\Python313\Scripts\strix.exe`.
- Decisão do usuário: **não** adicionar essa pasta ao PATH do Windows (uso restrito
  a este projeto/pack). Sempre invocar pelo caminho completo do `.exe` quando for
  rodar um scan aqui.

## O que falta / próximo passo recomendado

- Docker Desktop instalado mas **daemon não estava rodando** na checagem de
  2026-08-27 (`docker info` falhou: "cannot find the file specified" no pipe do
  Windows). Antes do primeiro scan real: usuário precisa abrir o Docker Desktop.
- `STRIX_LLM` + `LLM_API_KEY` ainda não configurados (nenhuma env var setada).
  Usuário confirmou que pode usar chave da OpenAI (`STRIX_LLM="openai/gpt-5.4"` ou
  similar) — só falta ele fornecer a chave na hora de rodar o primeiro scan.
- Alternativa sem Docker/chave local: opção gerenciada via `app.strix.ai` (skill
  `managed-pentesting-with-strix`), não configurada ainda.
