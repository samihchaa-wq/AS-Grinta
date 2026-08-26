"""Recupere TOUS les evenements de l'equipe (curseur 'prev' = remonte le temps)."""
import json
import os
import client

T = 48346
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'events.json')


def crawl_all():
    url = 'teams/%d/events/?season=%d' % (T, 2213845)
    seen = {}
    visited = set()
    while url and url not in visited:
        visited.add(url)
        page = client.get(url)
        if '__error__' in page:
            raise RuntimeError(page)
        for e in page['results']:
            seen.setdefault(e['id'], e)
        link = page.get('_links', {}).get('prev')
        if not link:
            break
        url = link['url'].split('/v2.1/', 1)[1]
    return list(seen.values())


if __name__ == '__main__':
    ev = crawl_all()
    ev.sort(key=lambda e: e['start_at'] or '')
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(ev, f, ensure_ascii=False)
    print('evenements:', len(ev))
    per = {}
    for e in ev:
        per.setdefault(e['season']['name'], []).append(e)
    for k in sorted(per):
        types = {}
        for e in per[k]:
            types[e['category']['type']] = types.get(e['category']['type'], 0) + 1
        print(k, len(per[k]), types)
