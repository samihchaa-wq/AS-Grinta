"""Extraction complete: 1 objet par match, avec presents, buteurs, HDM, composition.

Aucune donnee personnelle sensible (ni email, ni telephone, ni date de naissance).
Reprise automatique: relancer le script reprend la ou il s'est arrete.
"""
import json
import os
import sys
import time
import client

T = 48346
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'matches_full.json')
MATCH_TYPES = {'championship_match', 'friendly_match', 'cup_match',
               'tournament', 'challenge_match'}
TYPE_FR = {
    'championship_match': 'championnat',
    'friendly_match': 'amical',
    'challenge_match': 'entre_nous',
    'cup_match': 'coupe',
    'tournament': 'tournoi',
}

events = json.load(open(os.path.join(HERE, 'events.json'), encoding='utf-8'))
past = [e for e in events if e['category']['type'] in MATCH_TYPES and e.get('is_past')]
past.sort(key=lambda e: e['start_at'] or '')

out = {}
if os.path.exists(OUT):
    out = json.load(open(OUT, encoding='utf-8'))

t0 = time.time()
for i, e in enumerate(past):
    key = str(e['id'])
    if key in out:
        continue

    ol, orr = e.get('opponent_left') or {}, e.get('opponent_right') or {}
    ours = ol if ol.get('is_current_team') else orr
    them = orr if ol.get('is_current_team') else ol
    loc = e.get('location') or {}

    m = {
        'sporteasy_id': e['id'],
        'saison': (e.get('season') or {}).get('name'),
        'date': (e.get('start_at') or '')[:10],
        'heure': (e.get('start_at') or '')[11:16],
        'fin': (e.get('end_at') or '')[11:16],
        'type': TYPE_FR.get(e['category']['type'], e['category']['type']),
        'type_sporteasy': e['category']['type'],
        'competition': e['category'].get('localized_name'),
        'journee': e['category'].get('championship_day'),
        'intitule': e.get('name'),
        'adversaire': them.get('full_name'),
        'adversaire_id': them.get('id'),
        'domicile': bool(ours.get('is_home')),
        'adresse': loc.get('formatted_address'),
        'stade': loc.get('name'),
        'lat': loc.get('lat'),
        'lng': loc.get('lng'),
        'annule': bool(e.get('is_cancelled')),
        'score_grinta': ours.get('score'),
        'score_adverse': them.get('score'),
        'resultat': ours.get('match_outcome'),
        'presents': [],
        'absents': [],
        'buteurs': [],
        'passeurs': [],
        'cartons': [],
        'hdm': [],
        'composition': None,
        'alertes': [],
    }

    # --- presence nominative (toujours accessible) ---
    pr = client.get('teams/%d/events/%d/profiles/' % (T, e['id']))
    if '__error__' in pr:
        m['alertes'].append('presence indisponible (%s)' % pr['__error__'])
    else:
        for g in pr.get('attendees', []):
            for r in g['results']:
                entry = {
                    'nom': r['profile']['full_name'],
                    'profil_id': r['profile']['id'],
                    'motif': (r.get('presence') or {}).get('localized_name'),
                    'role': (r.get('role') or {}).get('localized_name'),
                }
                if g.get('attendance_status') == 'present':
                    m['presents'].append(entry)
                elif g.get('attendance_status') == 'absent':
                    m['absents'].append(entry)

    # --- buts, passes, cartons, HDM ---
    st = client.get('teams/%d/events/%d/stats/players/ranking/' % (T, e['id']))
    if '__error__' in st:
        m['alertes'].append('stats indisponibles (%s)' % st['__error__'])
    else:
        for p in st.get('players', []):
            nom = p['profile']['full_name']
            vals = {s['slug_name']: s['value'] for s in p['stats']}
            if vals.get('player_goals'):
                m['buteurs'].append({'nom': nom, 'buts': vals['player_goals']})
            if vals.get('player_assists'):
                m['passeurs'].append({'nom': nom, 'passes': vals['player_assists']})
            cj, cr = vals.get('yellow_cards') or 0, vals.get('red_cards') or 0
            if cj or cr:
                m['cartons'].append({'nom': nom, 'jaunes': cj, 'rouges': cr})
            if vals.get('man_of_event'):
                m['hdm'].append(nom)

    # --- composition (refusee quand elle n'existe pas ou n'est pas publiee) ---
    ln = client.get('teams/%d/events/%d/lineups/' % (T, e['id']))
    if '__error__' in ln:
        m['alertes'].append('composition indisponible (%s)' % ln['__error__'])
    else:
        noms = {}
        for g in ln.get('attendees', []):
            for r in g['results']:
                noms[r['profile']['id']] = r['profile']['full_name']
        lus = ln.get('lineups') or []
        cfg = (ln.get('config') or {}).get('coordinates') or {}
        mx, my = cfg.get('max_x') or 390, cfg.get('max_y') or 560
        for side in ('opponent_left', 'opponent_right'):
            blk = (lus[0] if lus else {}).get(side) or {}
            if not blk.get('field'):
                continue
            m['composition'] = {
                'formation': (blk.get('tactic') or {}).get('localized_name'),
                'titulaires': [{
                    'nom': noms.get(f['profile_id']),
                    'profil_id': f['profile_id'],
                    'ordre': f.get('order'),
                    'poste': (f.get('tactic_position') or {}).get('localized_name'),
                    'poste_court': (f.get('tactic_position') or {}).get('localized_name_short'),
                    'x_pct': round(100.0 * (f.get('coordinates') or {}).get('x', 0) / mx, 2),
                    'y_pct': round(100.0 * (f.get('coordinates') or {}).get('y', 0) / my, 2),
                } for f in blk['field']],
                'remplacants': [{'nom': noms.get(pid), 'profil_id': pid}
                                for pid in (blk.get('bench') or [])],
            }
            break

    # --- controles de coherence ---
    if m['score_grinta'] is not None and not m['annule']:
        try:
            total = sum(b['buts'] for b in m['buteurs'])
            if total != int(m['score_grinta']):
                m['alertes'].append('buteurs (%d) != score Grinta (%s)'
                                    % (total, m['score_grinta']))
        except (TypeError, ValueError):
            pass
    if not m['annule'] and m['score_grinta'] is None:
        m['alertes'].append('score jamais saisi')

    out[key] = m
    if i % 10 == 0:
        json.dump(out, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
        sys.stderr.write('%d/%d  %.0fs\n' % (len(out), len(past), time.time() - t0))
        sys.stderr.flush()

json.dump(out, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('termine: %d matchs, %.0fs' % (len(out), time.time() - t0))
