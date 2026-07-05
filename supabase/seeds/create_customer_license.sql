-- Trading Desk: create a customer license
--
-- Usage:
-- 1. Create the customer in Supabase Authentication -> Users first.
-- 2. Run the first query below to find the user's auth UID.
-- 3. Replace the placeholder values in the insert statement.
-- 4. Run the verification query at the end.

-- Find the auth user you just created.
select id, email, created_at
from auth.users
order by created_at desc;

-- Replace the values below before running.
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
  'CUSTOMER_USER_UID',
  'TD-PRO-002',
  'pro',
  'active',
  1,
  now() + interval '30 days',
  jsonb_build_object(
    'source', 'manual-admin',
    'customer_name', 'Customer Name',
    'notes', 'First paid license'
  )
);

-- Verify the created license.
select
  l.id,
  l.license_key,
  l.plan,
  l.status,
  l.max_devices,
  l.expires_at,
  l.metadata,
  u.email
from public.licenses l
join auth.users u on u.id = l.user_id
where l.license_key = 'TD-PRO-002';
