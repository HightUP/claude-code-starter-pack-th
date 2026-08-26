#!/usr/bin/env bash
# pre-commit-security-gate.sh
# Roda apenas em `git commit`. Bloqueia commits que tocam área sensível
# (webhook/callback externo, auth/sessão, Dockerfile, integração de pagamento)
# a não ser que a mensagem do commit já traga a marca de que a skill
# `security-check` rodou antes.
#
# Por quê: skill de segurança é sob demanda (só roda se alguém pedir) — um
# hook determinístico é o único jeito de garantir que ela seja invocada em
# TODA mudança sensível, não só quando alguém lembra de pedir.
set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Ativa só pra git commit (push não recebe mensagem nova pra checar a marca)
if ! echo "$COMMAND" | grep -qE '^git commit\b'; then
  exit 0
fi

# Padrões de path considerados sensíveis (case-insensitive). Ajuste pro seu
# projeto: o objetivo é cobrir autenticação/sessão, webhooks/callbacks de
# integração externa, containerização e fluxos de pagamento/dinheiro real.
SENSITIVE_PATTERNS=(
  'Dockerfile'
  'docker-compose'
  '(^|/)proxy\.ts$'
  '(^|/)middleware\.ts$'
  '(^|/)login/'
  '(^|/)auth/'
  '(^|/)lib/supabase/'
  'webhook'
  'callback'
  '(^|/)pagamento'
  '(^|/)payment'
  '/inter/'
  'migrations?/.*\.sql$'
)

STAGED=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
[ -z "$STAGED" ] && exit 0

sensitive_files=""
while IFS= read -r file; do
  [ -z "$file" ] && continue
  for pattern in "${SENSITIVE_PATTERNS[@]}"; do
    if echo "$file" | grep -qiE "$pattern"; then
      sensitive_files+="  • $file\n"
      break
    fi
  done
done <<< "$STAGED"

[ -z "$sensitive_files" ] && exit 0

# Marca de que a skill já rodou pra esse commit — o próprio texto da mensagem
# de commit (incluindo corpo em heredoc) chega inteiro em $COMMAND, então não
# precisa reconstruir a mensagem separadamente.
if echo "$COMMAND" | grep -qiE 'Security-check:'; then
  exit 0
fi

echo "🛡️  Este commit toca área sensível de segurança:" >&2
echo -e "$sensitive_files" >&2
echo "Antes de commitar, invoque a skill 'security-check' nesses arquivos." >&2
echo "Depois, refaça o commit incluindo no final da mensagem uma linha:" >&2
echo "  Security-check: ok (sem findings críticos)" >&2
echo "  — ou, se achou e corrigiu algo —" >&2
echo "  Security-check: findings corrigidos (resumo curto)" >&2
echo "Se for falso positivo (arquivo não é sensível de verdade), comite manualmente fora do Claude." >&2
exit 2
