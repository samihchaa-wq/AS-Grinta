-- Enrich known match venues without inventing information for ambiguous places.
--
-- The application deliberately keeps a single free-form address field. This
-- migration normalizes only venues whose equipment name and postal address
-- have been verified. Ambiguous historical locations (Pibrac boulevard des
-- Ecoles, 110 avenue du Marquisat, 17 chemin de la Saudrune) are intentionally
-- left untouched.
--
-- Historical matches are carried by historical_match_scores. The lifecycle
-- guard intentionally prevents rewriting finished matches in public.matches,
-- so only upcoming matches are normalized there.

create temporary table venue_address_map (
  old_address text primary key,
  new_address text not null
) on commit drop;

insert into venue_address_map (old_address, new_address) values
  ('223 Rue des Arts, 31670 Labège, France',
   'Complexe Sportif de Toulouse INP - 223 Rue des Arts - 31670 - Labège'),
  ('Complexe Sportif de l''AS INP, 223 Rue des Arts, 31670 Labège',
   'Complexe Sportif de Toulouse INP - 223 Rue des Arts - 31670 - Labège'),
  ('Allée de la Colombe, 31770 Colomiers, France',
   'Complexe sportif André-Roux - Allée de la Colombe - 31770 - Colomiers'),
  ('20 Chemin de Garric, 31200 Toulouse, France',
   'Complexe sportif du TOAC - 20 Chemin de Garric - 31200 - Toulouse'),
  ('8 bis Rue Claudius Rougenet, 31500 Toulouse, France',
   'Stade Michel Saraiba - 8 bis Rue Claudius Rougenet - 31500 - Toulouse'),
  ('Stade AS Hersoise - 8 bis Rue Claudius Rougenet, 31500 Toulouse, France',
   'Stade Michel Saraiba - 8 bis Rue Claudius Rougenet - 31500 - Toulouse'),
  ('8 Rue Claudius Rougenet, 31500 Toulouse, France',
   'Stade Michel Saraiba - 8 bis Rue Claudius Rougenet - 31500 - Toulouse'),
  ('Chemin des Garrosses, 31180 Rouffiac-Tolosan, France',
   'Complexe sportif - Chemin des Garrosses - 31180 - Rouffiac-Tolosan'),
  ('Chemin de la Cepière, 31100 Toulouse, France',
   'Marcel Cerdan - 7 Chemin de la Cépière - 31100 - Toulouse'),
  ('Stade Marcel Cerdan, Chemin de la Cépière, 31100 Toulouse, France',
   'Marcel Cerdan - 7 Chemin de la Cépière - 31100 - Toulouse'),
  ('Rte du Stade, 31700 Cornebarrieu, France',
   'Stade Municipal - 4 Route du Stade - 31700 - Cornebarrieu'),
  ('Boulevard Als Cambiots, 31130 Balma, France',
   'Parc Lagarde - Boulevard Als Cambiots - 31130 - Balma'),
  ('Rue des Cyclamens, 31700 Blagnac, France',
   'Complexe sportif des Barradels - Rue des Cyclamens - 31700 - Blagnac'),
  ('Impasse Barthe, 31200 Toulouse, France',
   'Toulouse-Lautrec - 26 Impasse Barthe - 31200 - Toulouse'),
  ('Chemin des Côtes de Pech David, 31400 Toulouse, France',
   'Robert Barran - 82 Chemin des Côtes de Pech David - 31400 - Toulouse'),
  ('153 Avenue de Lardenne, 31100 Toulouse, France',
   'Stade Aurélien Feuillet - 153 Avenue de Lardenne - 31100 - Toulouse'),
  ('Allée des Sports, 31170 Tournefeuille, France',
   'Stade de football - Allée des Sports - 31170 - Tournefeuille'),
  ('Avenue Jean Mermoz, 31140 Fonbeauzard, France',
   'Stade Municipal - Avenue Jean Mermoz - 31140 - Fonbeauzard'),
  ('Chemin du Dr Louis Delherm, 31320 Auzeville-Tolosane, France',
   'Stade Municipal - Chemin du Dr Louis Delherm - 31320 - Auzeville-Tolosane'),
  ('Rue de Rabastens, 31500 Toulouse, France',
   'Les Argoulets - 29 Rue de Rabastens - 31500 - Toulouse'),
  ('Rue du Stade, 31490 Brax, France',
   'Stade Municipal - Rue du Stade - 31490 - Brax'),
  ('Avenue de Lattre de Tassigny, 31400 Toulouse, France',
   'Corbarieu - 2 Avenue de Lattre de Tassigny - 31400 - Toulouse');

update public.historical_match_scores h
set address = m.new_address
from venue_address_map m
where h.address = m.old_address;

update public.matches mt
set address = m.new_address
from venue_address_map m
where mt.address = m.old_address
  and mt.status = 'a_venir';

update public.opponents o
set address = m.new_address
from venue_address_map m
where o.address = m.old_address;

update public.club_settings c
set home_address = m.new_address
from venue_address_map m
where c.home_address = m.old_address;
