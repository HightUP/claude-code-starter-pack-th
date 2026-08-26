#!/usr/bin/env bash
# pre-bash-guard.sh
# Bloqueia comandos destrutivos ou inseguros antes de executar.
# Comunicação com Claude Code:
#   - exit 0  → permite
#   - exit 2  → bloqueia e envia stderr de volta pro Claude
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Patterns proibidos. Cada linha é um regex (POSIX ERE — usado com grep -E).
# Cuidado ao alterar: padrões frouxos geram falso-positivo; ancore o destino
# do comando (espaço ou fim de linha) sempre que possível.
DANGEROUS_PATTERNS=(
  'rm -rf +/([[:space:]]|$)'        # `rm -rf /` literal, não `rm -rf /tmp/...`
  'rm -rf +\*([[:space:]]|$)'
  'rm -rf +~([[:space:]]|$)'
  '> +/dev/sd[a-z]'
  'dd .*of=/dev/sd[a-z]'
  'mkfs\.'
  ':\(\)\{ *:\|: *& *\};:'           # fork bomb
  'curl [^|]* \| *(sh|bash)'
  'wget [^|]* \| *(sh|bash)'
  'chmod -R 777 +/([[:space:]]|$)'
  '\bDROP DATABASE\b'
  '\bDROP TABLE\b'
  '\bTRUNCATE TABLE\b'
  'git push +(--force|-f) +origin +(main|master|production)\b'
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qE "$pattern"; then
    echo "🚫 Comando bloqueado pelo pre-bash-guard: padrão '$pattern' detectado." >&2
    echo "Se for intencional, execute manualmente no terminal." >&2
    exit 2
  fi
done

# Avisa (não bloqueia) sobre comandos sensíveis em paths protegidos.
# Ancora `rm` no início de um comando (após start, ;, &, |) e só inspeciona
# argumentos até o próximo separador, evitando falso-positivo quando o nome
# sensível aparece em outro comando da mesma linha.
if echo "$COMMAND" | grep -qE '(^|[;&|]) *rm [^;&|]*(\.env(\.|$|[[:space:]/])|/secrets/|/credentials(\.|/))'; then
  echo "⚠️  Tentativa de remover arquivo sensível. Confirme se é intencional." >&2
  exit 2
fi

# `docker build --build-arg NOME=valor` com nome de secret: mesmo problema do
# `ARG` em Dockerfile (fica gravado em docker history), só que passado direto
# na linha de comando em vez de commitado — pre-commit-secrets.sh não pega
# isso porque não há arquivo staged nenhum.
if echo "$COMMAND" | grep -qE 'docker (buildx )?build\b' \
  && echo "$COMMAND" | grep -qiE -- '--build-arg[= ][A-Za-z0-9_]*(SECRET|KEY|TOKEN|PASSWORD|PASSWD|CREDENTIAL|PRIVATE)[A-Za-z0-9_]*='; then
  echo "🚫 '--build-arg' com nome de secret detectado. ARGs ficam gravados na imagem (docker history)." >&2
  echo "Use 'docker build --secret id=...' + 'RUN --mount=type=secret' no Dockerfile, ou injete só em runtime." >&2
  exit 2
fi

exit 0
