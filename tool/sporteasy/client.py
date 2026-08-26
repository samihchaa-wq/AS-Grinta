import os, json, urllib.request, urllib.error, http.cookiejar

BASE = "https://api.sporteasy.net/"
CJFILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cookies.txt")
cj = http.cookiejar.MozillaCookieJar(CJFILE)
if os.path.exists(CJFILE):
    cj.load(ignore_discard=True, ignore_expires=True)
op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
UA = ('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120 Safari/537.36')


def _h(extra=None):
    h = {'User-Agent': UA, 'Accept': 'application/json',
         'Origin': 'https://app.sporteasy.net',
         'Referer': 'https://app.sporteasy.net/'}
    if extra:
        h.update(extra)
    return h


def csrf():
    for c in cj:
        if c.name == 'se_csrftoken':
            return c.value
    return ''


def login():
    op.open(urllib.request.Request(BASE + "v2.1/account/csrf/", headers=_h()), timeout=30).read()
    data = json.dumps({"username": os.environ['SE_EMAIL'],
                       "password": os.environ['SE_PASS']}).encode()
    r = op.open(urllib.request.Request(
        BASE + "v2.1/account/authenticate/", data=data, method='POST',
        headers=_h({'Content-Type': 'application/json', 'X-CSRFToken': csrf()})), timeout=30)
    out = r.read()
    cj.save(ignore_discard=True, ignore_expires=True)
    return out


def get(path, version="v2.1", raw=False, tries=4):
    """GET avec reprise sur coupure reseau (l'API ferme parfois la connexion)."""
    import time
    url = BASE + version + "/" + path.lstrip("/")
    last = None
    for attempt in range(tries):
        try:
            r = op.open(urllib.request.Request(url, headers=_h({'X-CSRFToken': csrf()})),
                        timeout=45)
            b = r.read()
            return b if raw else json.loads(b)
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504) and attempt < tries - 1:
                last = e
                time.sleep(2 ** attempt)
                continue
            return {"__error__": e.code, "__body__": e.read()[:300].decode('utf-8', 'replace'),
                    "__url__": url}
        except Exception as e:  # coupure reseau, timeout, JSON tronque
            last = e
            if attempt < tries - 1:
                time.sleep(2 ** attempt)
                continue
    return {"__error__": "network", "__body__": repr(last)[:300], "__url__": url}
