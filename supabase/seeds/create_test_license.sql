-- 1. Find the auth user you just created.
select id, email, created_at
from auth.users
order by created_at desc;

-- 2. Replace USER_UID below with the selected auth.users.id.
insert into public.licenses (
  user_id,
  license_key,
  plan,
  status,
  max_devices,
  expires_at,
  metadata
)
values (
  'USER_UID',
  'TD-PRO-001',
  'pro',
  'active',
  1,
  now() + interval '30 days',
  jsonb_build_object(
    'source', 'manual-seed',
    'notes', 'Initial online license test'
  )
);

-- 3. Verify the license row.
select
  l.id,
  l.license_key,
  l.status,
  l.max_devices,
  l.expires_at,
  u.email
from public.licenses l
join auth.users u on u.id = l.user_id
order by l.created_at desc;
