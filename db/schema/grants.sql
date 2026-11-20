do $$
begin
    if not exists (
        select 1
        from pg_roles
        where rolname = 'inspector'
    ) then
        create role inspector login password 'NetoSQL2025';
    else
        alter role inspector login password 'NetoSQL2025';
    end if;
end
$$;

grant all privileges on schema korniichuk_food to inspector;
grant usage on schema information_schema, pg_catalog, exts to inspector;

grant all privileges
on all tables in schema korniichuk_food
to inspector;

grant all privileges
on all sequences in schema korniichuk_food
to inspector;

grant execute
on all routines in schema korniichuk_food
to inspector;

grant execute
on function exts.uuid_generate_v4()
to inspector;
