-- The Minecraft encyclopedia makes the Wiki much larger: lift the 100-row cap of the read functions to 500.
do $$
declare
  fn text;
  def text;
begin
  for fn in select unnest(array['public.get_public_wiki(text,integer)','public.participant_get_wiki(text,integer)']) loop
    def := pg_get_functiondef(fn::regprocedure);
    if def like '%least(coalesce(p_limit,100),100)%' then
      execute replace(def, 'least(coalesce(p_limit,100),100)', 'least(coalesce(p_limit,100),500)');
    end if;
  end loop;
end $$;
