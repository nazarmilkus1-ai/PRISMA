create table if not exists public.iris_clan_import_archive(
  id uuid primary key default gen_random_uuid(),
  source_number integer not null,
  clan_name text not null,
  leader_name text,
  leader_username text,
  founded_at date,
  original_members jsonb not null default '[]'::jsonb,
  transfer_status text not null,
  imported_at timestamptz not null default now(),
  unique(source_number,clan_name)
);
alter table public.iris_clan_import_archive enable row level security;

insert into public.iris_clan_import_archive
(source_number,clan_name,leader_name,leader_username,founded_at,original_members,transfer_status)
values
(18,'FGK','Karlik','andrisol',date '2026-09-10','[{"name":"Karlik","username":"andrisol","role":"leader"}]'::jsonb,'ARCHIVED_NO_CURRENT_PRISMA_MEMBER'),
(17,'литвин легенда','Nd0ve','nd0ve',date '2026-08-25','[{"name":"ㅤ","username":"","role":"member"},{"name":"даня 17/0/0","username":"h1gannn","role":"member"},{"name":"Nd0ve","username":"nd0ve","role":"leader"}]'::jsonb,'ARCHIVED_NO_CURRENT_PRISMA_MEMBER'),
(16,'Династия Фараона','faraon','facenull',date '2026-08-19','[{"name":"император планеты","username":"bmbrx1","role":"member"},{"name":"faraon","username":"facenull","role":"leader"},{"name":"P.S.I.X","username":"psiixxo","role":"member"},{"name":"virtxak","username":"virtxak","role":"member"},{"name":"Bob","username":"bobminec","role":"member"}]'::jsonb,'ACTIVE_IN_PRISMA'),
(15,'HD','HellDive','holediver',date '2026-08-17','[{"name":"The dumbest Minecraft player","username":"sakigo","role":"member"},{"name":"APTG","username":"aptgsus","role":"member"},{"name":"HellDive","username":"holediver","role":"leader"}]'::jsonb,'ACTIVE_IN_PRISMA_PARTIAL'),
(13,'OW2','MrAnonchik','ano_n_chik',date '2026-07-28','[{"name":"ляля","username":"h1tori_gotou","role":"member"},{"name":"MrAnonchik","username":"ano_n_chik","role":"leader"}]'::jsonb,'ARCHIVED_NO_CURRENT_PRISMA_MEMBER'),
(11,'war resurrection','zorro','zorro_270',date '2026-06-12','[{"name":"zares","username":"zizosr","role":"member"},{"name":"fckkkgoyim","username":"fckkkgoyim","role":"member"},{"name":"8501556412","username":"","role":"member"},{"name":"zorro","username":"zorro_270","role":"leader"}]'::jsonb,'ARCHIVED_NO_CURRENT_PRISMA_LEADER'),
(9,'天堂','MKuNDvK','nomfish',date '2026-06-09','[{"name":"bananaxd","username":"pipisn7","role":"member"},{"name":"назар на самом деле узбек","username":"goose5551803","role":"member"},{"name":"пузотряс","username":"ortemdyrka","role":"member"},{"name":"бисмилях","username":"extazysexy","role":"member"},{"name":"Зам.начальника ГО","username":"urbex071","role":"member"},{"name":"Cmoor6840","username":"cmoor6840","role":"member"},{"name":"C|S|L","username":"sharzho221","role":"member"},{"name":"корделиус","username":"","role":"member"},{"name":"ዘꤕተ ዘተꤕ","username":"ignorchiikk","role":"member"},{"name":"MKuNDvK","username":"nomfish","role":"leader"}]'::jsonb,'ACTIVE_IN_PRISMA_PARTIAL')
on conflict(source_number,clan_name) do update set
leader_name=excluded.leader_name,leader_username=excluded.leader_username,founded_at=excluded.founded_at,
original_members=excluded.original_members,transfer_status=excluded.transfer_status,imported_at=now();