#!/usr/bin/env bash
# git_push_producao.sh
#
# Script de push manual para o repositorio ia51-portal-teste (deploy automatico
# do site ia51mais.com via GitHub Actions -> FTP).
#
# O que ele faz:
#   1. Localiza a chave SSH de deploy persistida numa pasta irma do repo
#      (../../ia51-deploy-key/id_ed25519_ia51_push a partir da localizacao
#      deste script), para funcionar em qualquer sessao futura sem precisar
#      regravar a chave.
#   2. Anexa essa chave ao GIT_SSH_COMMAND ja existente no ambiente (que traz
#      o ProxyCommand necessario para alcancar o github.com) - NUNCA reescreve
#      essa variavel do zero.
#   3. Roda "git push origin main" na raiz do repo, repassando quaisquer
#      argumentos extras recebidos por este script ("$@").
#
# Uso:
#   bash deploy_automacao/git_push_producao.sh
#   bash deploy_automacao/git_push_producao.sh --dry-run   (por exemplo)

set -euo pipefail

# Diretorio onde este script esta fisicamente localizado (resolve symlinks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Raiz do repo = dois niveis acima deste script (deploy_automacao/ -> raiz do repo)
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)/ia51-portal-teste"

# Chave persistida como pasta irma do repo: ia51-deploy-key/
KEY_PATH="$(cd "$SCRIPT_DIR/../.." && pwd)/ia51-deploy-key/id_ed25519_ia51_push"

if [ ! -f "$KEY_PATH" ]; then
  echo "ERRO: chave nao encontrada em: $KEY_PATH" >&2
  exit 1
fi

# Anexa a chave ao GIT_SSH_COMMAND ja existente no ambiente (nunca reescrever do zero)
export GIT_SSH_COMMAND="$GIT_SSH_COMMAND -i \"$KEY_PATH\" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

git -C "$REPO_ROOT" push origin main "$@"
