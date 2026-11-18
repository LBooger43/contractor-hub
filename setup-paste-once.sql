-- ONE paste for Contractor Hub + Limpiempo (Supabase › SQL Editor › New query › Run). Safe to run more than once.

-- Contractor Hub: job chat + subcontractors.
-- Paste into Supabase › SQL Editor › New query › Run. Safe to run more than once.

-- ---------- job chat ----------
create table if not exists messages (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  client_id uuid references clients(id) on delete cascade,      -- null = whole-crew chat
  user_id uuid not null default auth.uid(),
  body text not null default '' check (char_length(body) <= 2000),
  photo text check (photo is null or char_length(photo) <= 450000), -- small JPEG, made on the phone
  tags uuid[] not null default '{}',                               -- people looped in with @
  pinned boolean not null default false,
  flag_open boolean not null default false,
  flagged_by uuid,
  resolved_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists messages_biz_time on messages (business_id, created_at desc);
alter table messages enable row level security;

drop policy if exists msg_read on messages;
create policy msg_read on messages for select using (business_id = my_business());
drop policy if exists msg_insert on messages;
create policy msg_insert on messages for insert
  with check (business_id = my_business() and user_id = auth.uid() and pinned = false and flag_open = false);
drop policy if exists msg_delete on messages;
create policy msg_delete on messages for delete
  using (business_id = my_business() and (user_id = auth.uid() or my_role() = 'owner'));

-- Pin / flag / resolve go through this function so nobody can edit someone else's words.
create or replace function msg_mark(p_id uuid, p_what text)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if p_what = 'pin' then
    update messages set pinned = not pinned where id = p_id and business_id = my_business();
  elsif p_what = 'flag' then
    update messages set flag_open = true, flagged_by = auth.uid(), resolved_by = null where id = p_id and business_id = my_business();
  elsif p_what = 'resolve' then
    update messages set flag_open = false, resolved_by = auth.uid() where id = p_id and business_id = my_business();
  else
    return false;
  end if;
  return found;
end $$;
grant execute on function msg_mark(uuid, text) to authenticated;

-- ---------- subcontractors (owner only) ----------
create table if not exists subs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  trade text not null default '',
  phone text not null default '',
  email text not null default '',
  coi_expires date,                 -- insurance certificate expiration
  w9 boolean not null default false,
  owed numeric(10,2) not null default 0 check (owed >= 0),
  paid_ytd numeric(10,2) not null default 0 check (paid_ytd >= 0),
  notes text not null default '',
  created_at timestamptz not null default now()
);
alter table subs enable row level security;
drop policy if exists subs_owner on subs;
create policy subs_owner on subs for all
  using (business_id = my_business() and my_role() = 'owner')
  with check (business_id = my_business() and my_role() = 'owner');


-- Owner invite codes: nobody can start a NEW business without a code from Leif.
-- Existing businesses (Rosa, Wayne, Chepe) and crew joining with a crew code are not affected.
create table if not exists owner_codes (
  code text primary key,
  uses_left int not null default 1 check (uses_left >= 0),
  note text not null default '',
  created_at timestamptz not null default now()
);
alter table owner_codes enable row level security;   -- no policies: only the sign-up function can read it

insert into owner_codes (code, uses_left, note) values
  ('HUB-JAXN-KE66', 1, 'Contractor Hub owner'),  ('HUB-HH9Y-DVJH', 1, 'Contractor Hub owner'),  ('HUB-9U4R-Y454', 1, 'Contractor Hub owner'),  ('HUB-2KC7-ZVCT', 1, 'Contractor Hub owner'),  ('HUB-MB59-JMYX', 1, 'Contractor Hub owner'),
  ('LIMPIO-84YB-TU87', 1, 'Limpiempo owner'),  ('LIMPIO-8H4A-XZBU', 1, 'Limpiempo owner'),  ('LIMPIO-53TR-EC37', 1, 'Limpiempo owner')
on conflict (code) do nothing;

-- New sign-up path: needs a code. p_app picks the owner's color.
create or replace function create_business_v2(p_code text, p_business text, p_name text, p_phone text default '', p_app text default 'limpiempo')
returns uuid language plpgsql security definer set search_path = public as $$
declare b uuid; ok int;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if exists (select 1 from members where user_id = auth.uid()) then raise exception 'Already in a business'; end if;
  update owner_codes set uses_left = uses_left - 1 where upper(code) = upper(trim(coalesce(p_code,''))) and uses_left > 0;
  get diagnostics ok = row_count;
  if ok = 0 then raise exception 'BAD_CODE'; end if;
  insert into businesses (name, phone) values (trim(p_business), coalesce(p_phone,'')) returning id into b;
  insert into members (user_id, business_id, name, role, color, phone)
    values (auth.uid(), b, trim(p_name), 'owner', case when p_app = 'chub' then '#1F6FEB' else '#D6245E' end, coalesce(p_phone,''));
  return b;
end $$;
grant execute on function create_business_v2(text, text, text, text, text) to authenticated;

-- Close the old no-code door.
create or replace function create_business(p_business text, p_name text, p_phone text default '')
returns uuid language plpgsql security definer set search_path = public as $$
begin raise exception 'BAD_CODE'; end $$;

-- To add more codes later (Supabase › SQL Editor):
--   insert into owner_codes (code, uses_left, note) values ('HUB-NEW1-CODE', 1, 'for Mike');
-- To see which codes are left:
--   select code, uses_left, note from owner_codes order by created_at;
