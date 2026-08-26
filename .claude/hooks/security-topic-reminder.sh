#!/usr/bin/env bash
# security-topic-reminder.sh
# Roda em UserPromptSubmit. Se a mensagem do usuário tocar em área sensível de
# segurança (auth, pagamento, banco, upload, webhook, etc.), injeta um lembrete
# pra invocar a skill `security-check` naquela tarefa.
#
# Por quê: `security-check` é sob demanda e o `pre-commit-security-gate.sh` só
# bloqueia no `git commit` — entre esses dois pontos, uma conversa inteira pode
# rolar sobre algo sensível sem a auditoria específica do projeto (RLS do
# Supabase, webhook com dupla confirmação, etc.) ser lembrada. Este hook fecha
# esse intervalo, sem bloquear nada (só some contexto).
set -uo pipefail

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""')

KEYWORDS='senha|password|login|autentica|\bauth\b|sess(a|ã)o|(access|auth|api|refresh|session)[_ -]?token|token de (acesso|sess(a|ã)o|autentica[cç][aã]o)|jwt|permiss(a|ã)o|\brbac\b|\brole\b|\badmin\b|pagamento|payment|\bpix\b|cart(a|ã)o|stripe|webhook|callback|upload|anexo|banco de dados|database|\bsql\b|\brls\b|supabase|migration|credencial|api[_ ]?key|secret|criptograf|senha.*hash|hash.*senha|password.*hash|cookie|\bcors\b|\bcsrf\b|\bxss\b|\bsqli\b|injection|vulnerabilidade|invadir|hacke(ar|r)|pentest|exploit'

if ! echo "$PROMPT" | grep -qiE "$KEYWORDS"; then
  exit 0
fi

cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"[security-topic-reminder] Esta mensagem toca em área sensível de segurança (auth/pagamento/banco/upload/webhook/credencial/etc). Antes de considerar a tarefa concluída, invoque a skill `security-check` sobre o código relevante — ela cobre secrets, injeção, AuthN/AuthZ, webhooks, RLS do Supabase, uploads e logs, e não é substituída pelas checagens genéricas automáticas do plugin security-guidance. Se a mensagem for só uma pergunta conceitual sem código envolvido, ignore este lembrete."}}
EOF
exit 0
