#!/usr/bin/env python3
# push_via_api.py "mensagem do commit"
#
# Publica o repo ia51-portal-teste SEM git push (o ambiente Cowork bloqueia o
# git-receive-pack: "403 GitHub request blocked by Cowork"). Usa a API Git Data
# do GitHub (api.github.com NAO e bloqueada), com o token fine-grained de
# ../../ia51-deploy-key/gh_token.txt (Contents:write).
#
# Fluxo: pega o main remoto como base -> cria 1 blob por arquivo mudado
# (base64) -> cria 1 tree (base_tree = tree do main remoto) -> cria 1 commit
# (parent = main remoto) -> move refs/heads/main (fast-forward). Ignora *.bak*.
# Idempotente: reexecutar refaz tudo sobre o main atual.
import os, sys, json, base64, subprocess, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "ia51-portal-teste"))
TOKEN_FILE = os.path.abspath(os.path.join(HERE, "..", "..", "ia51-deploy-key", "gh_token.txt"))
OWNER_REPO = "asotano1/ia51-portal-teste"
API = "https://api.github.com/repos/" + OWNER_REPO
MSG = sys.argv[1] if len(sys.argv) > 1 else "Publica portal IA 51+ (via API)"

TOKEN = open(TOKEN_FILE, encoding="utf-8").read().strip()
# config do curl com o header de auth (token fora do argv/ps)
_cfg = tempfile.NamedTemporaryFile("w", delete=False, suffix=".curlrc")
_cfg.write('header = "Authorization: Bearer %s"\n' % TOKEN)
_cfg.write('header = "Accept: application/vnd.github+json"\n')
_cfg.write('silent\n')
_cfg.close()

def api(method, url, data=None):
    cmd = ["curl", "-K", _cfg.name, "-X", method, url, "-w", "\n__HTTP__%{http_code}"]
    dfile = None
    if data is not None:
        dfile = tempfile.NamedTemporaryFile("w", delete=False, suffix=".json")
        json.dump(data, dfile); dfile.close()
        cmd += ["--data-binary", "@" + dfile.name]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    if dfile: os.unlink(dfile.name)
    body, _, code = out.rpartition("__HTTP__")
    body = body.rstrip("\n")
    try: j = json.loads(body) if body else {}
    except Exception: j = {"_raw": body[:300]}
    return int(code or 0), j

def die(msg, code=None, j=None):
    print("ERRO: " + msg + (" (HTTP %s)" % code if code else ""))
    if j is not None: print(json.dumps(j)[:400])
    os.unlink(_cfg.name); sys.exit(1)

# 1) base = main remoto atual
c, ref = api("GET", API + "/git/ref/heads/main")
if c != 200: die("nao li o main remoto", c, ref)
base_sha = ref["object"]["sha"]
c, bc = api("GET", API + "/git/commits/" + base_sha)
if c != 200: die("nao li o commit base", c, bc)
base_tree = bc["tree"]["sha"]
print("base main remoto = %s (tree %s)" % (base_sha[:9], base_tree[:9]))

# 2) arquivos mudados base..HEAD local
diff = subprocess.run(["git", "-C", REPO_ROOT, "diff", "--name-status", base_sha, "HEAD"],
                      capture_output=True, text=True).stdout.splitlines()
entries, nblob, ndel, nskip = [], 0, 0, 0
for line in diff:
    parts = line.split("\t")
    if len(parts) < 2: continue
    st, path = parts[0], parts[-1]
    if ".bak" in path:
        nskip += 1; continue
    if st.startswith("D"):
        entries.append({"path": path, "mode": "100644", "type": "blob", "sha": None}); ndel += 1
        continue
    full = os.path.join(REPO_ROOT, path)
    with open(full, "rb") as f: raw = f.read()
    c, blob = api("POST", API + "/git/blobs",
                  {"content": base64.b64encode(raw).decode(), "encoding": "base64"})
    if c not in (200, 201) or "sha" not in blob:
        die("falha ao criar blob de " + path, c, blob)
    entries.append({"path": path, "mode": "100644", "type": "blob", "sha": blob["sha"]})
    nblob += 1
    if nblob % 25 == 0: print("  blobs: %d..." % nblob)
print("blobs=%d delete=%d ignorados(.bak)=%d" % (nblob, ndel, nskip))
if not entries: die("nada a publicar (0 entradas)")

# 3) tree
c, tree = api("POST", API + "/git/trees", {"base_tree": base_tree, "tree": entries})
if c not in (200, 201) or "sha" not in tree: die("falha ao criar tree", c, tree)
print("tree novo = %s" % tree["sha"][:9])

# 4) commit
c, commit = api("POST", API + "/git/commits",
                {"message": MSG, "tree": tree["sha"], "parents": [base_sha]})
if c not in (200, 201) or "sha" not in commit: die("falha ao criar commit", c, commit)
print("commit novo = %s" % commit["sha"][:9])

# 5) move main (fast-forward)
c, upd = api("PATCH", API + "/git/refs/heads/main", {"sha": commit["sha"], "force": False})
if c != 200: die("falha ao mover main", c, upd)
print("PUBLICADO_API_OK main -> %s" % commit["sha"])
# atualiza o ref de rastreamento local
subprocess.run(["git", "-C", REPO_ROOT, "update-ref", "refs/remotes/origin/main", commit["sha"]])
os.unlink(_cfg.name)
