-- PRISMA v2: defense-in-depth for future public functions.
-- PostgreSQL grants EXECUTE to PUBLIC for new functions by default. The
-- project's current hosted configuration does not persist the equivalent
-- ALTER DEFAULT PRIVILEGES override, so enforce opt-in execution with a DDL
-- event trigger. Existing functions are intentionally left untouched; their
-- migrations must carry explicit grants.

create or replace function private.prisma_revoke_public_function_execute()
returns event_trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  command_row record;
begin
  for command_row in
    select *
    from pg_event_trigger_ddl_commands()
    where command_tag = 'CREATE FUNCTION'
      and schema_name = 'public'
      and object_type = 'function'
  loop
    execute format(
      'revoke execute on function %s from public',
      command_row.object_identity
    );
  end loop;
end;
$function$;

drop event trigger if exists prisma_revoke_public_function_execute;

create event trigger prisma_revoke_public_function_execute
on ddl_command_end
when tag in ('CREATE FUNCTION')
execute function private.prisma_revoke_public_function_execute();

revoke all on function private.prisma_revoke_public_function_execute()
from public, anon, authenticated, service_role;

grant execute on function private.prisma_revoke_public_function_execute()
to postgres;