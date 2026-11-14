#!/usr/bin/env bash
# git_push_producao.sh
#
# Script de push para o repositorio ia51-portal-teste (deploy automatico do
# site ia51mais.com via GitHub Actions -> FTP).
#
# Ordem de envio (a rota SSH da nuvem anda sendo derrubada pelo proxy em
# 13-14/11/2026 -> por isso HTTPS primeiro):
#   1. HTTPS com token fine-grained persistido em ../../ia51-deploy-key/gh_token.txt
#      (so permissao Contents:write no repo). Preferido quando o arquivo existe.
#   2. Reserva: SSH com a chave persistida ../../ia51-deploy-key/id_ed25519_ia51_push,
#      anexada ao GIT_SSH_COMMAND ja existente (que traz o ProxyCommand) - NUNCA
#      reescreve essa variavel do zero.
# Nunca usa pull/merge/rebase/--force. Repassa argumentos extras ("$@").
#
# Uso:
#   bash deploy_automacao/git_push_producao.sh

set -euo pipefail

# Diretorio onde este script esta fisicamente localizado
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Raiz do repo = dois niveis acima deste script (deploy_automacao/ -> raiz do repo)
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)/ia51-portal-teste"

# Credenciais persistidas na pasta irma do repo: ia51-deploy-key/
KEY_PATH="$(cd "$SCRIPT_DIR/../.." && pwd)/ia51-deploy-key/id_ed25519_ia51_push"
TOKEN_FILE="$(cd "$SCRIPT_DIR/../.." && pwd)/ia51-deploy-key/gh_token.txt"
HTTPS_URL="https://github.com/asotano1/ia51-portal-teste.git"

# 1) Preferir HTTPS com token quando existir
if [ -s "$TOKEN_FILE" ]; then
  TOKEN="$(tr -d ' \t\r\n' < "$TOKEN_FILE")"
  BASIC="$(printf 'x-access-token:%s' "$TOKEN" | base64 -w0)"
  if [ -n "$TOKEN" ] && git -C "$REPO_ROOT" \
       -c http.extraHeader="Authorization: Basic $BASIC" \
       push "$HTTPS_URL" HEAD:main "$@"; then
    # mantem o ref de rastreamento local em dia (push por URL nao atualiza sozinho)
    git -C "$REPO_ROOT" update-ref refs/remotes/origin/main HEAD 2>/dev/null || true
    exit 0
  fi
  echo "AVISO: push por HTTPS (token) falhou; tentando SSH como reserva..." >&2
fi

# 2) Reserva: SSH com a chave persistida
if [ ! -f "$KEY_PATH" ]; then
  echo "ERRO: sem token utilizavel e chave SSH nao encontrada em: $KEY_PATH" >&2
  exit 1
fi
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -i \"$KEY_PATH\" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
git -C "$REPO_ROOT" push origin main "$@"
