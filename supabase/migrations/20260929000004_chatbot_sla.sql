-- Chatbot retrieval function + escalation SLA helper
create or replace function match_kb(query_embedding vector(384), match_count int default 6,
                                    min_similarity float default 0.35)
returns table(id bigint, source text, heading text, content text, similarity float)
language sql stable security definer set search_path = public as $$
  select id, source, heading, content, 1 - (embedding <=> query_embedding) as similarity
  from kb_chunks
  where 1 - (embedding <=> query_embedding) >= min_similarity
  order by embedding <=> query_embedding
  limit match_count
$$;

-- Marks overdue coaching and returns who to chase (used by daily-scheduler)
create or replace function flag_sla_breaches()
returns table(escalation_id uuid, trainee text, pending_coaches text[], hr_email text, manager_email text)
language sql security definer set search_path = public as $$
  with b as (
    update escalations set state = 'sla_breached'
    where state = 'coaching' and sla_due < now()
    returning id, trainee_id)
  select b.id, t.full_name,
         array(select p.email from coaching_sessions cs join profiles p on p.id = cs.coach_id
               where cs.escalation_id = b.id and cs.decision is null),
         (select email from profiles where id = t.hr_id),
         (select email from profiles where id = t.manager_id)
  from b join profiles t on t.id = b.trainee_id
$$;
