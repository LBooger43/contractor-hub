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
