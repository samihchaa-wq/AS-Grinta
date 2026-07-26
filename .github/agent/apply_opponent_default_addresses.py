from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"Marker missing: {label}")
    return text.replace(old, new, 1)


repo = Path("lib/features/matches/data/matches_repository.dart")
text = repo.read_text()
text = replace_once(
    text,
    """  Future<void> setMatchAddress({
    required String matchId,
    required String? address,
  }) async {
    await _client.rpc(
      'admin_set_match_address',
      params: {'p_match_id': matchId, 'p_address': address},
    );
  }
""",
    """  Future<void> setMatchAddress({
    required String matchId,
    required String? address,
    required bool rememberAsDefault,
  }) async {
    await _client.rpc(
      'admin_set_match_address',
      params: {
        'p_match_id': matchId,
        'p_address': address,
        'p_remember_as_default': rememberAsDefault,
      },
    );
  }
""",
    "repository RPC",
)
repo.write_text(text)

controller = Path("lib/features/matches/presentation/matches_controller.dart")
text = controller.read_text()
text = replace_once(
    text,
    """    int? squadSizeLimit,
    String? address,
  }) async {
""",
    """    int? squadSizeLimit,
    String? address,
    bool rememberAddressAsDefault = false,
  }) async {
""",
    "create signature",
)
text = replace_once(
    text,
    """      await _repository.setMatchAddress(matchId: matchId, address: address);
""",
    """      await _repository.setMatchAddress(
        matchId: matchId,
        address: address,
        rememberAsDefault: rememberAddressAsDefault,
      );
""",
    "create address call",
)
update_start = text.index("  Future<void> updateMatch({")
prefix, suffix = text[:update_start], text[update_start:]
suffix = replace_once(
    suffix,
    """    int? squadSizeLimit,
    String? address,
  }) async {
""",
    """    int? squadSizeLimit,
    String? address,
    bool rememberAddressAsDefault = false,
  }) async {
""",
    "update signature",
)
suffix = replace_once(
    suffix,
    """      await _repository.setMatchAddress(matchId: id, address: address);
""",
    """      await _repository.setMatchAddress(
        matchId: id,
        address: address,
        rememberAsDefault: rememberAddressAsDefault,
      );
""",
    "update address call",
)
controller.write_text(prefix + suffix)

form = Path("lib/features/matches/presentation/match_form_page.dart")
text = form.read_text()
text = replace_once(
    text,
    """  bool _squadLimitLoaded = false;

  /// Adresse du terrain d'AS Grinta""",
    """  bool _squadLimitLoaded = false;
  bool _rememberAddressAsDefault = false;

  /// Adresse du terrain d'AS Grinta""",
    "form state",
)
text = replace_once(
    text,
    """                helperText: 'Terrain de l’équipe qui reçoit. Mémorisée et '
                    'préremplie aux prochains matchs.',
""",
    """                helperText: 'Préremplie depuis l’équipe qui reçoit. La modification '
                    'reste propre à ce match sauf option ci-dessous.',
""",
    "helper text",
)
text = replace_once(
    text,
    """            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<bool>(
""",
    """            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _rememberAddressAsDefault,
              onChanged: (value) => setState(
                () => _rememberAddressAsDefault = value ?? false,
              ),
              title: const Text(
                'Utiliser cette adresse par défaut pour les prochains matchs',
              ),
              subtitle: Text(
                _isHome
                    ? 'Met à jour le terrain par défaut d’AS Grinta.'
                    : 'Met à jour le terrain par défaut de l’adversaire.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<bool>(
""",
    "checkbox",
)
text = replace_once(
    text,
    """        address: address.isEmpty ? null : address,
      );
""",
    """        address: address.isEmpty ? null : address,
        rememberAddressAsDefault: _rememberAddressAsDefault,
      );
""",
    "create submit",
)
update_start = text.index("      await notifier.updateMatch(")
prefix, suffix = text[:update_start], text[update_start:]
suffix = replace_once(
    suffix,
    """        address: address.isEmpty ? null : address,
      );
""",
    """        address: address.isEmpty ? null : address,
        rememberAddressAsDefault: _rememberAddressAsDefault,
      );
""",
    "update submit",
)
form.write_text(prefix + suffix)

Path("supabase/migrations/20260726200000_opponent_default_addresses.sql").write_text("""begin;

drop function if exists public.admin_set_match_address(uuid, text);

create function public.admin_set_match_address(
  p_match_id uuid,
  p_address text,
  p_remember_as_default boolean default false
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_address text := nullif(btrim(p_address), '');
  v_opponent uuid;
  v_location text;
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if v_address is not null and char_length(v_address) > 300 then
    raise exception 'Address cannot exceed 300 characters' using errcode = '22023';
  end if;

  update public.matches
  set address = v_address
  where id = p_match_id
  returning opponent_id, location into v_opponent, v_location;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  if coalesce(p_remember_as_default, false) and v_address is not null then
    if v_location = 'domicile' then
      update public.club_settings set home_address = v_address where id;
    elsif v_opponent is not null then
      update public.opponents set address = v_address where id = v_opponent;
    end if;
  end if;
end;
$function$;

revoke all on function public.admin_set_match_address(uuid, text, boolean)
from public, anon;
grant execute on function public.admin_set_match_address(uuid, text, boolean)
to authenticated;

update public.opponents
set address = case lower(btrim(name))
  when 'toac foot loisir 1' then '20 Chemin de Garric, 31200 Toulouse, France'
  when 'toac foot loisir 2' then '20 Chemin de Garric, 31200 Toulouse, France'
  when 'as hersoise' then '8 bis Rue Claudius Rougenet, 31500 Toulouse, France'
  when 'amical olympique cornebarrieu' then 'Rte du Stade, 31700 Cornebarrieu, France'
  when 'positive vibration' then 'Boulevard Als Cambiots, 31130 Balma, France'
  when 'rouffiac tolosan fc' then 'Chemin des Garrosses, 31180 Rouffiac-Tolosan, France'
  else address
end
where lower(btrim(name)) in (
  'toac foot loisir 1',
  'toac foot loisir 2',
  'as hersoise',
  'amical olympique cornebarrieu',
  'positive vibration',
  'rouffiac tolosan fc'
);

commit;
""")

Path("supabase/tests/database/opponent_default_addresses.test.sql").write_text("""begin;
set local search_path = public, extensions, pg_catalog;
select plan(2);

select has_function(
  'public',
  'admin_set_match_address',
  array['uuid', 'text', 'boolean'],
  'le RPC accepte le choix explicite de mémorisation'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.admin_set_match_address(uuid,text,boolean)',
    'EXECUTE'
  ),
  'le RPC reste inaccessible aux anonymes'
);

select * from finish();
rollback;
""")
