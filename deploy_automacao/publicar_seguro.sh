#!/usr/bin/env bash
# publicar_seguro.sh "mensagem do commit"
#
# Faz tudo de uma vez: rsync do site -> limpa cadeados do git (mv, nunca rm,
# porque o mount do Cowork nao deixa apagar arquivos em .git/) -> add -> commit
# -> push. Pode rodar de novo sem medo: se nao ha nada novo, nao commita e
# so tenta o push. NUNCA usa --force, pull, merge ou rebase.
#
# Saida final (ultima linha): PUBLICADO_OK | SEM_MUDANCAS | BLOQUEADO_REJEITADO | ERRO_<motivo>

set -uo pipefail
MSG="${1:-Publica portal IA 51+ - $(date +%d/%m/%Y)}"
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SD/../.." && pwd)"            # pasta do projeto
REPO="$ROOT/ia51-portal-teste"
SITE="$ROOT/site_ia51mais"
TS="$(date +%s)"

limpar_locks() {
  # mv funciona onde rm falha. Varre todos os .lock do .git (ignora os ja renomeados).
  find "$REPO/.git" -name '*.lock' -type f 2>/dev/null | while read -r f; do
    mv "$f" "${f%.lock}.lock.cleared_$TS$RANDOM" 2>/dev/null || true
  done
}

git_retry() {   # tenta ate 4x, limpando cadeados entre as tentativas
  local n=0
  while [ $n -lt 4 ]; do
    limpar_locks
    if git -C "$REPO" "$@" >/tmp/git_out.txt 2>&1; then cat /tmp/git_out.txt | grep -v 'unable to unlink' ; return 0; fi
    # se foi rejeicao do remoto, nao insiste
    if grep -qE 'rejected|fetch first|non-fast-forward' /tmp/git_out.txt; then cat /tmp/git_out.txt; return 99; fi
    n=$((n+1)); sleep 1
  done
  cat /tmp/git_out.txt | tail -5
  return 1
}

# 1) sincroniza site -> repo
rsync -a \
  --exclude='ga4_bundle_py.zip' --exclude='ga4_update_bundle.zip' \
  --exclude='index.html.bak_seo_20260901' --exclude='indexnovo.html' \
  --exclude='teste.txt' --exclude='zirSyQGO' \
  "$SITE/" "$REPO/" || { echo "ERRO_RSYNC"; exit 1; }

# 2) add + commit (so se houver mudanca)
git_retry add -A || { echo "ERRO_GIT_ADD"; exit 1; }
limpar_locks
if git -C "$REPO" diff --cached --quiet 2>/dev/null; then
  echo "(nada novo pra commitar)"
else
  git_retry commit -q -m "$MSG" || { echo "ERRO_GIT_COMMIT"; exit 1; }
fi
limpar_locks

# 3) push (repete se houver commit local ainda nao enviado)
AHEAD="$(git -C "$REPO" rev-list --count origin/main..HEAD 2>/dev/null || echo 1)"
if [ "$AHEAD" = "0" ]; then echo "SEM_MUDANCAS"; exit 0; fi
bash "$SD/git_push_producao.sh" 2>&1 | grep -v 'unable to unlink' | tail -8
RC=${PIPESTATUS[0]}
limpar_locks
if [ "$RC" != "0" ]; then
  if git -C "$REPO" status -sb 2>/dev/null | head -1 | grep -q 'ahead'; then echo "BLOQUEADO_REJEITADO_OU_ERRO_PUSH"; else echo "ERRO_PUSH"; fi
  exit 1
fi
echo "PUBLICADO_OK"
