-- =========================================================
-- Fotos do casamento — rode este arquivo inteiro no
-- Supabase: SQL Editor > New query > colar > Run
-- =========================================================

-- 1) Código do casamento (vai no QR code). TROQUE o valor abaixo.
create table if not exists public.evento (
  id int primary key default 1 check (id = 1),
  codigo text not null
);
insert into public.evento (codigo) values ('ANAERAFA101026')
on conflict (id) do update set codigo = excluded.codigo;

-- 2) Tabelas
create table if not exists public.convidados (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (char_length(trim(nome)) between 1 and 80),
  criado_em timestamptz not null default now()
);

create table if not exists public.fotos (
  id uuid primary key default gen_random_uuid(),
  convidado_id uuid not null references public.convidados(id) on delete cascade,
  caminho text not null unique,
  criado_em timestamptz not null default now()
);
-- Nome normalizado (sem acento, minúsculo): "João  Silva" e "joao silva" são a mesma pessoa
create extension if not exists unaccent schema extensions;
alter table public.convidados add column if not exists nome_chave text;
create unique index if not exists convidados_nome_chave_idx on public.convidados (nome_chave);

create index if not exists fotos_convidado_idx on public.fotos (convidado_id);
create index if not exists fotos_criado_idx on public.fotos (criado_em desc);

-- RLS ligado e sem policies: ninguém lê/escreve as tabelas direto.
-- Todo acesso passa pelas funções abaixo.
alter table public.evento enable row level security;
alter table public.convidados enable row level security;
alter table public.fotos enable row level security;

-- 3) Funções auxiliares
create or replace function public.codigo_ok(p_codigo text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from evento where codigo = p_codigo);
$$;

-- Uma foto "conta" se já foi enviada ou se foi reservada há menos de 10 min
-- (reservas abandonadas liberam a vaga sozinhas).
create or replace function public.fotos_usadas(p_convidado uuid)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from fotos f
  where f.convidado_id = p_convidado
    and (f.criado_em > now() - interval '10 minutes'
         or exists (select 1 from storage.objects o
                    where o.bucket_id = 'fotos' and o.name = f.caminho));
$$;

-- 4) Funções chamadas pelo site
create or replace function public.normalizar_nome(p text)
returns text language sql stable set search_path = public, extensions as $$
  select lower(unaccent(regexp_replace(trim(coalesce(p, '')), '\s+', ' ', 'g')));
$$;

-- Login só com o nome. O mesmo nome sempre cai na MESMA conta,
-- então entrar de novo (em outro celular, aba anônima etc.) não dá 20 fotos extras.
drop function if exists public.registrar_convidado(text, text);
create or replace function public.entrar_convidado(p_nome text, p_codigo text)
returns table (id uuid, nome text)
language plpgsql security definer set search_path = public as $$
declare
  v_nome text := regexp_replace(trim(coalesce(p_nome, '')), '\s+', ' ', 'g');
  v_chave text := normalizar_nome(p_nome);
begin
  if not codigo_ok(p_codigo) then raise exception 'codigo_invalido'; end if;
  if array_length(string_to_array(v_chave, ' '), 1) < 2 or char_length(v_chave) < 5 then
    raise exception 'nome_incompleto';
  end if;

  insert into convidados (nome, nome_chave) values (v_nome, v_chave)
  on conflict (nome_chave) do nothing;

  return query select c.id, c.nome from convidados c where c.nome_chave = v_chave;
end $$;

create or replace function public.reservar_foto(p_convidado uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_caminho text;
begin
  -- trava o convidado para evitar envios simultâneos furando o limite
  perform 1 from convidados where id = p_convidado for update;
  if not found then raise exception 'convidado_invalido'; end if;

  -- apaga reservas abandonadas deste convidado
  delete from fotos f
  where f.convidado_id = p_convidado
    and f.criado_em <= now() - interval '10 minutes'
    and not exists (select 1 from storage.objects o
                    where o.bucket_id = 'fotos' and o.name = f.caminho);

  if fotos_usadas(p_convidado) >= 20 then raise exception 'limite_atingido'; end if;

  v_caminho := gen_random_uuid()::text || '.jpg';
  insert into fotos (convidado_id, caminho) values (p_convidado, v_caminho);
  return v_caminho;
end $$;

create or replace function public.liberar_foto(p_convidado uuid, p_caminho text)
returns void language sql security definer set search_path = public as $$
  delete from fotos f
  where f.convidado_id = p_convidado and f.caminho = p_caminho
    and not exists (select 1 from storage.objects o
                    where o.bucket_id = 'fotos' and o.name = p_caminho);
$$;

create or replace function public.minhas_fotos(p_convidado uuid)
returns table (caminho text, criado_em timestamptz)
language sql stable security definer set search_path = public as $$
  select f.caminho, f.criado_em from fotos f
  where f.convidado_id = p_convidado
    and exists (select 1 from storage.objects o
                where o.bucket_id = 'fotos' and o.name = f.caminho)
  order by f.criado_em;
$$;

create or replace function public.listar_fotos(p_codigo text, p_limite int default 60, p_antes timestamptz default null)
returns table (caminho text, nome text, criado_em timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not codigo_ok(p_codigo) then raise exception 'codigo_invalido'; end if;
  return query
    select f.caminho, c.nome, f.criado_em
    from fotos f join convidados c on c.id = f.convidado_id
    where exists (select 1 from storage.objects o
                  where o.bucket_id = 'fotos' and o.name = f.caminho)
      and (p_antes is null or f.criado_em < p_antes)
    order by f.criado_em desc
    limit least(greatest(p_limite, 1), 100);
end $$;

-- Usada pela policy do Storage: só aceita upload de caminho reservado
create or replace function public.reserva_valida(p_caminho text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from fotos
                 where caminho = p_caminho
                   and criado_em > now() - interval '10 minutes');
$$;

-- 5) Permissões
revoke all on function public.codigo_ok(text) from public;
revoke all on function public.fotos_usadas(uuid) from public;
revoke all on function public.normalizar_nome(text) from public;
grant execute on function
  public.entrar_convidado(text, text),
  public.reservar_foto(uuid),
  public.liberar_foto(uuid, text),
  public.minhas_fotos(uuid),
  public.listar_fotos(text, int, timestamptz),
  public.reserva_valida(text)
to anon, authenticated;

-- 6) Bucket de fotos (público para leitura, só JPEG, máx. 5 MB)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos', 'fotos', true, 5242880, array['image/jpeg'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "upload somente com reserva" on storage.objects;
create policy "upload somente com reserva" on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'fotos' and public.reserva_valida(name));
