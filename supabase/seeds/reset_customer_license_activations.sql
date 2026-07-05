-- Trading Desk: reset one customer's device activations
--
-- Use this when:
-- - the customer changes laptop/PC
-- - the customer hits max_devices
-- - you want to force a clean re-activation

delete from public.license_activations
where license_id in (
  select id
  from public.licenses
  where license_key = 'TD-PRO-002'
);

-- Optional verification.
select
  l.license_key,
  a.device_id,
  a.device_name,
  a.activated_at,
  a.last_seen_at
from public.license_activations a
join public.licenses l on l.id = a.license_id
where l.license_key = 'TD-PRO-002'
order by a.activated_at desc;
