begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  to_regclass('public.guest_players') is not null
  and to_regprocedure('public.admin_get_guest_players(boolean)') is not null
  and to_regprocedure(
    'public.admin_add_or_reuse_match_guest(uuid,uuid,text,text,boolean,text)'
  ) is not null,
  'le catalogue et les RPC invités existent'
);

select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.guest_players'::regclass
  ),
  'RLS est activée sur le catalogue des invités'
);

select ok(
  (
    select is_nullable = 'YES'
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'match_sport_participants'
      and column_name = 'season_player_id'
  )
  and exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'match_sport_participants'
      and column_name = 'guest_player_id'
  ),
  'un participant peut désormais porter une identité permanente ou invitée'
);

select is(
  (
    select count(*)
    from unnest(array[
      'public.admin_get_guest_players(boolean)',
      'public.admin_get_match_guests(uuid)',
      'public.admin_add_or_reuse_match_guest(uuid,uuid,text,text,boolean,text)',
      'public.admin_remove_match_guest(uuid,uuid,text)',
      'public.admin_set_guest_archived(uuid,boolean,text)'
    ]::text[]) expected(signature)
    join pg_proc procedure on procedure.oid = to_regprocedure(expected.signature)
    where procedure.prosecdef
  ),
  0::bigint,
  'les RPC publiques invités restent SECURITY INVOKER'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.admin_get_guest_players(boolean)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.admin_add_or_reuse_match_guest(uuid,uuid,text,text,boolean,text)',
    'EXECUTE'
  ),
  'le rôle anonyme ne peut utiliser aucune RPC invité'
);

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    'a1000000-0000-0000-0000-000000000001',
    'guest-admin@example.invalid',
    '{"first_name":"Admin","last_name":"Invités"}'::jsonb
  ),
  (
    'a1000000-0000-0000-0000-000000000002',
    'guest-player@example.invalid',
    '{"first_name":"Joueur","last_name":"Invités"}'::jsonb
  );

update public.profiles
set role = case
      when id = 'a1000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id in (
  'a1000000-0000-0000-0000-000000000001',
  'a1000000-0000-0000-0000-000000000002'
);

insert into public.seasons(id, name, status)
values ('a2000000-0000-0000-0000-000000000001', '2097-2098', 'open');

insert into public.opponents(id, name)
values ('a3000000-0000-0000-0000-000000000001', 'Invités FC');

insert into public.season_players(
  id,
  season_id,
  first_name,
  last_name,
  is_goalkeeper,
  is_active,
  position,
  profile_id
)
values
  (
    'a4000000-0000-0000-0000-000000000001',
    'a2000000-0000-0000-0000-000000000001',
    'Permanent',
    'Un',
    false,
    true,
    1,
    'a1000000-0000-0000-0000-000000000002'
  ),
  (
    'a4000000-0000-0000-0000-000000000002',
    'a2000000-0000-0000-0000-000000000001',
    'Permanent',
    'Deux',
    false,
    true,
    2,
    'a1000000-0000-0000-0000-000000000001'
  );

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'a1000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.guest_match',
  public.create_match_with_odds_and_sport_limit(
    'a2000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000001',
    ((now() + interval '5 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '5 days') at time zone 'Europe/Paris')::time,
    'domicile',
    2.10,
    3.20,
    2.90,
    14
  )::text,
  true
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.admin_get_guest_players(false)$$,
  '42501',
  'Active administrator role required',
  'un joueur ne peut pas lire le catalogue invité'
);

select throws_ok(
  $$select public.admin_add_or_reuse_match_guest(
    current_setting('test.guest_match')::uuid,
    null,
    'Alex',
    null,
    false,
    'Tentative joueur'
  )$$,
  '42501',
  'Active administrator role required',
  'un joueur ne peut pas ajouter un invité'
);

select throws_ok(
  $$insert into public.guest_players(
    first_name, created_by, updated_by
  ) values (
    'Direct',
    'a1000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000002'
  )$$,
  '42501',
  null,
  'aucune écriture directe dans le catalogue n’est possible'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.guest_add_result',
  public.admin_add_or_reuse_match_guest(
    current_setting('test.guest_match')::uuid,
    null,
    'Alex',
    'Gardien',
    true,
    'Premier renfort'
  )::text,
  true
);

select set_config(
  'test.guest_id',
  (
    current_setting('test.guest_add_result')::jsonb
    ->> 'guest_player_id'
  ),
  true
);

select set_config(
  'test.guest_participant',
  (
    current_setting('test.guest_add_result')::jsonb
    ->> 'participant_id'
  ),
  true
);

select is(
  public.admin_get_guest_players(false) #>> '{guests,0,display_name}',
  'Alex Gardien (Invité)',
  'le nouvel invité est réutilisable et clairement identifié'
);

select is(
  public.admin_get_match_guests(
    current_setting('test.guest_match')::uuid
  ) #>> '{guests,0,participant_id}',
  current_setting('test.guest_participant'),
  'l’invité est rattaché au match'
);

reset role;

select ok(
  exists (
    select 1
    from public.match_sport_participants participant
    where participant.id = current_setting('test.guest_participant')::uuid
      and participant.season_player_id is null
      and participant.guest_player_id =
        current_setting('test.guest_id')::uuid
      and participant.is_eligible
      and participant.availability_status = 'not_applicable'
      and participant.convocation_status = 'convoked'
      and participant.waitlist_turn_state = 'not_applicable'
  ),
  'l’invité est convoqué sans disponibilité ni tour de liste d’attente'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_add_or_reuse_match_guest(
    current_setting('test.guest_match')::uuid,
    null,
    ' alex ',
    'gardien',
    true,
    'Réutilisation exacte'
  ) #>> '{participant_id}',
  current_setting('test.guest_participant'),
  'une identité identique réutilise le même participant de match'
);

select is(
  jsonb_array_length(
    public.admin_get_guest_players(false) -> 'guests'
  ),
  1,
  'la réutilisation exacte ne crée pas de doublon dans le catalogue'
);

select private.sync_match_sport_workflow(
  current_setting('test.guest_match')::uuid
);

select is(
  (
    select participant.is_eligible
    from public.match_sport_participants participant
    where participant.id = current_setting('test.guest_participant')::uuid
  ),
  true,
  'une synchronisation ultérieure du match conserve les invités'
);

select is(
  (
    select (item ->> 'is_guest')::boolean
    from jsonb_array_elements(
      public.admin_get_match_convocations(
        current_setting('test.guest_match')::uuid
      ) -> 'players'
    ) item
    where item ->> 'participant_id' =
      current_setting('test.guest_participant')
  ),
  true,
  'les convocations administrateur exposent l’identité invitée'
);

reset role;

update public.match_sport_participants
set availability_status = 'available',
    availability_updated_at = now(),
    availability_updated_by = 'a1000000-0000-0000-0000-000000000001',
    convocation_status = 'convoked',
    updated_at = now()
where match_id = current_setting('test.guest_match')::uuid
  and season_player_id is not null;

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_save_match_composition(
    current_setting('test.guest_match')::uuid,
    'Libre',
    (
      select jsonb_agg(
        jsonb_build_object(
          'participant_id', ranked.id,
          'zone', case
            when ranked.guest_player_id is not null then 'field'
            when ranked.permanent_rank = 1 then 'field'
            else 'bench'
          end,
          'x', case
            when ranked.guest_player_id is not null then 0.5
            when ranked.permanent_rank = 1 then 0.5
            else null
          end,
          'y', case
            when ranked.guest_player_id is not null then 0.1
            when ranked.permanent_rank = 1 then 0.7
            else null
          end,
          'slot_label', case
            when ranked.guest_player_id is not null then 'GK'
            else null
          end,
          'sort_order', ranked.sort_order
        )
        order by ranked.sort_order
      )
      from (
        select
          participant.id,
          participant.season_player_id,
          participant.guest_player_id,
          row_number() over (
            partition by (participant.guest_player_id is null)
            order by participant.season_player_id
          ) as permanent_rank,
          row_number() over (
            order by participant.guest_player_id nulls last,
              participant.season_player_id
          ) as sort_order
        from public.match_sport_participants participant
        where participant.match_id =
          current_setting('test.guest_match')::uuid
          and participant.is_eligible
      ) ranked
    ),
    false,
    'Composition avec invité'
  ) #>> '{has_goalkeeper_warning}',
  'false',
  'un invité gardien placé sur le terrain satisfait l’avertissement gardien'
);

select is(
  (
    select item ->> 'display_name'
    from jsonb_array_elements(
      public.admin_get_match_composition(
        current_setting('test.guest_match')::uuid
      ) -> 'entries'
    ) item
    where item ->> 'participant_id' =
      current_setting('test.guest_participant')
  ),
  'Alex Gardien (Invité)',
  'le brouillon prépare un libellé invité explicite'
);

select is(
  public.admin_publish_match_composition(
    current_setting('test.guest_match')::uuid,
    false,
    'Publication avec invité'
  ) #>> '{version}',
  '1',
  'la composition avec invité se publie normalement'
);

select is(
  (
    select (item ->> 'is_guest')::boolean
    from jsonb_array_elements(
      public.get_published_match_composition(
        current_setting('test.guest_match')::uuid
      ) -> 'entries'
    ) item
    where item ->> 'participant_id' =
      current_setting('test.guest_participant')
  ),
  true,
  'le snapshot public conserve le marqueur invité'
);

select public.admin_set_guest_archived(
  current_setting('test.guest_id')::uuid,
  true,
  'Pause du catalogue'
);

select is(
  jsonb_array_length(
    public.admin_get_guest_players(false) -> 'guests'
  ),
  0,
  'un invité archivé disparaît du catalogue réutilisable'
);

select is(
  jsonb_array_length(
    public.admin_get_guest_players(true) -> 'guests'
  ),
  1,
  'un invité archivé reste consultable par le staff'
);

select is(
  jsonb_array_length(
    public.admin_get_match_guests(
      current_setting('test.guest_match')::uuid
    ) -> 'guests'
  ),
  1,
  'l’archivage ne retire jamais l’invité de son match existant'
);

select public.admin_remove_match_guest(
  current_setting('test.guest_match')::uuid,
  current_setting('test.guest_participant')::uuid,
  'Renfort finalement absent'
);

select is(
  jsonb_array_length(
    public.admin_get_match_guests(
      current_setting('test.guest_match')::uuid
    ) -> 'guests'
  ),
  0,
  'le staff peut retirer l’invité du match courant'
);

reset role;

select ok(
  not exists (
    select 1
    from public.match_composition_entries entry
    where entry.match_id = current_setting('test.guest_match')::uuid
      and entry.participant_id =
        current_setting('test.guest_participant')::uuid
  )
  and exists (
    select 1
    from public.match_composition_publications publication,
      jsonb_array_elements(publication.snapshot -> 'entries') item
    where publication.match_id = current_setting('test.guest_match')::uuid
      and item ->> 'participant_id' =
        current_setting('test.guest_participant')
  ),
  'le retrait nettoie le brouillon mais préserve la publication historique'
);

update private.app_feature_flags
set enabled = false,
    updated_at = now(),
    updated_by = 'a1000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.admin_get_guest_players(false)$$,
  '42501',
  'Sports-management module is disabled',
  'le feature flag désactivé bloque le catalogue invité'
);

reset role;
select * from finish();
rollback;
