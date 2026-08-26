#!/usr/bin/env bash
# pre-commit-secrets.sh
# Roda apenas em comandos `git commit` / `git push`.
# Bloqueia se detectar padrões de secrets nos arquivos staged.
set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Ativa só pra git commit/push (early return em qualquer outra coisa)
if ! echo "$COMMAND" | grep -qE '^git (commit|push)'; then
  exit 0
fi

# Padrões de secrets (regex). Mantenha conservador pra evitar falsos positivos.
SECRET_PATTERNS=(
  '-----BEGIN (RSA|OPENSSH|EC|DSA|PGP) PRIVATE KEY-----'
  'AKIA[0-9A-Z]{16}'                              # AWS Access Key
  'aws_secret_access_key\s*=\s*[A-Za-z0-9/+=]{40}' # AWS Secret
  'ghp_[A-Za-z0-9]{36}'                            # GitHub PAT
  'gho_[A-Za-z0-9]{36}'                            # GitHub OAuth
  'sk-ant-api[0-9]{2}-[A-Za-z0-9_-]{90,}'          # Anthropic API key
  'sk-[A-Za-z0-9]{48}'                             # OpenAI key (legado)
  'xox[baprs]-[A-Za-z0-9-]{10,}'                   # Slack tokens
  'EAA[A-Za-z0-9]{50,}'                            # Meta/FB long-lived tokens
)

# Pega arquivos staged
STAGED=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
[ -z "$STAGED" ] && exit 0

found=""
while IFS= read -r file; do
  [ ! -f "$file" ] && continue
  # Pula binários
  if file "$file" 2>/dev/null | grep -q 'binary'; then continue; fi

  for pattern in "${SECRET_PATTERNS[@]}"; do
    if grep -qE "$pattern" "$file" 2>/dev/null; then
      found+="  • $file (padrão: $pattern)\n"
      break
    fi
  done
done <<< "$STAGED"

if [ -n "$found" ]; then
  echo "🚨 Possíveis secrets detectados nos arquivos staged:" >&2
  echo -e "$found" >&2
  echo "Remova os secrets ou mova-os para .env antes de commitar." >&2
  echo "Se for falso positivo, faça o commit manualmente fora do Claude." >&2
  exit 2
fi

# ARG de build com nome de secret em Dockerfile: vira parte permanente da
# imagem (visível via `docker history`/`docker inspect`), diferente de ENV
# setado em runtime. Doc oficial do Docker/BuildKit trata isso como anti-padrão
# (build check "SecretsUsedInArgOrEnv") — o certo é RUN --mount=type=secret.
# Exceção: NEXT_PUBLIC_* já é público por design (embutido no bundle do browser).
dockerfile_secrets=""
while IFS= read -r file; do
  [ ! -f "$file" ] && continue
  case "$(basename "$file")" in
    Dockerfile|Dockerfile.*|*.dockerfile) ;;
    *) continue ;;
  esac

  while IFS= read -r line; do
    arg_name=$(echo "$line" | sed -E 's/^ARG[[:space:]]+([A-Za-z0-9_]+).*/\1/')
    [ -z "$arg_name" ] && continue
    if echo "$arg_name" | grep -qiE '(SECRET|KEY|TOKEN|PASSWORD|PASSWD|CREDENTIAL|PRIVATE)' \
      && ! echo "$arg_name" | grep -qE '^NEXT_PUBLIC_'; then
      dockerfile_secrets+="  • $file: ARG $arg_name\n"
    fi
  done < <(grep -E '^ARG[[:space:]]+' "$file")
done <<< "$STAGED"

if [ -n "$dockerfile_secrets" ]; then
  echo "🚨 ARG de build com nome de secret detectado em Dockerfile:" >&2
  echo -e "$dockerfile_secrets" >&2
  echo "ARGs ficam gravados na imagem Docker (docker history), mesmo sem 'ser usados' de fato no build." >&2
  echo "Segredo deve ser lido só em runtime via variável de ambiente (process.env / os.environ), ou via 'RUN --mount=type=secret' no build. Nunca como ARG/ENV. Exceção: NEXT_PUBLIC_* (já é público por design)." >&2
  echo "Se for falso positivo, faça o commit manualmente fora do Claude." >&2
  exit 2
fi

# Camada extra opcional: se gitleaks estiver instalado, roda sobre os arquivos
# staged. Regex acima é hand-rolled (só os padrões que listamos); gitleaks tem
# regras mantidas pra centenas de provedores + detecção por entropia. Se não
# tiver instalado, segue só com o regex acima — não é dependência obrigatória.
if command -v gitleaks >/dev/null 2>&1; then
  if ! gitleaks_output=$(gitleaks protect --staged --no-banner --redact -v 2>&1); then
    echo "🚨 gitleaks encontrou possível secret nos arquivos staged:" >&2
    echo "$gitleaks_output" >&2
    echo "Remova o secret antes de commitar. Se for falso positivo, ajuste .gitleaks.toml ou commit manualmente fora do Claude." >&2
    exit 2
  fi
fi

exit 0
