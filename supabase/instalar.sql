-- =====================================================================
--  AMERO · Base de datos (web + sistema de gestión)
--  Cómo usarlo: Supabase → SQL Editor → New query → pegar TODO → Run.
--  Se puede volver a correr sin perder datos.
-- =====================================================================

create schema if not exists privado;

-- ---------------------------------------------------------------------
--  Tablas
-- ---------------------------------------------------------------------
create table if not exists public.admins (
  email  text primary key,
  creado timestamptz not null default now()
);

create table if not exists public.config (
  id      int primary key default 1 check (id = 1),
  negocio jsonb not null default '{}'::jsonb,   -- datos que muestra la web
  ajustes jsonb not null default '{}'::jsonb    -- ajustes del sistema
);

create table if not exists public.categorias (
  id          text primary key,
  nombre      text not null,
  tipo        text not null default 'botella',  -- dibujo provisorio en la web
  orden       int  not null default 0,
  restringida boolean not null default false     -- venta solo a mayores de 18
);

create table if not exists public.proveedores (
  id       uuid primary key default gen_random_uuid(),
  nombre   text not null,
  contacto text not null default '',
  telefono text not null default '',
  email    text not null default '',
  notas    text not null default '',
  creado   timestamptz not null default now()
);

create table if not exists public.productos (
  id            text primary key,
  codigo        text unique,
  nombre        text not null,
  detalle       text not null default '',
  categoria     text references public.categorias(id) on update cascade on delete set null,
  proveedor_id  uuid references public.proveedores(id) on delete set null,
  costo         numeric(12,2) not null default 0,
  precio        numeric(12,2) not null default 0,
  stock         int not null default 0,
  stock_min     int not null default 0,
  en_web        boolean not null default true,
  estrella      boolean not null default false,
  solo_consulta boolean not null default false,
  foto          text not null default '',
  orden         int not null default 0,
  creado        timestamptz not null default now(),
  actualizado   timestamptz not null default now()
);

create table if not exists public.cajas (
  id         uuid primary key default gen_random_uuid(),
  apertura   timestamptz not null default now(),
  cierre     timestamptz,
  inicial    numeric(12,2) not null default 0,
  movs       jsonb not null default '[]'::jsonb,
  esperado   numeric(12,2),
  contado    numeric(12,2),
  diferencia numeric(12,2),
  usuario    text
);
create unique index if not exists cajas_una_abierta on public.cajas ((true)) where cierre is null;

create table if not exists public.pedidos (
  id              uuid primary key default gen_random_uuid(),
  nro             bigint generated always as identity unique,
  fecha           timestamptz not null default now(),
  origen          text not null default 'web',
  cliente         text not null default '',
  telefono        text not null default '',
  entrega         text not null default '',
  nota            text not null default '',
  items           jsonb not null default '[]'::jsonb,
  total           numeric(12,2) not null default 0,
  precio_completo boolean not null default true,
  estado          text not null default 'pendiente' check (estado in ('pendiente','pagado','entregado','cancelado')),
  pago            text,
  pagado_en       timestamptz,
  entregado_en    timestamptz,
  cancelado_en    timestamptz,
  venta_id        uuid
);
create index if not exists pedidos_estado on public.pedidos (estado);

create table if not exists public.ventas (
  id         uuid primary key default gen_random_uuid(),
  nro        bigint generated always as identity unique,
  fecha      timestamptz not null default now(),
  items      jsonb not null,
  subtotal   numeric(12,2) not null default 0,
  descuento  numeric(12,2) not null default 0,
  total      numeric(12,2) not null default 0,
  pago       text not null,
  recibido   numeric(12,2),
  caja_id    uuid references public.cajas(id) on delete set null,
  pedido_id  uuid references public.pedidos(id) on delete set null,
  anulada    boolean not null default false,
  anulada_en timestamptz,
  usuario    text
);
create index if not exists ventas_fecha on public.ventas (fecha);
create index if not exists ventas_caja on public.ventas (caja_id);

create table if not exists public.compras (
  id           uuid primary key default gen_random_uuid(),
  fecha        timestamptz not null default now(),
  proveedor_id uuid references public.proveedores(id) on delete set null,
  comprobante  text not null default '',
  items        jsonb not null default '[]'::jsonb,
  total        numeric(12,2) not null default 0,
  usuario      text
);

create table if not exists public.ajustes_stock (
  id          uuid primary key default gen_random_uuid(),
  fecha       timestamptz not null default now(),
  producto_id text,
  nombre      text not null default '',
  antes       int not null,
  despues     int not null,
  motivo      text not null default '',
  usuario     text
);

-- ---------------------------------------------------------------------
--  Permisos: solo los emails de la tabla admins pueden ver y tocar datos.
--  La web pública solo puede leer el catálogo y crear pedidos (funciones abajo).
-- ---------------------------------------------------------------------
create or replace function privado.es_admin() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.admins a
                 where lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;

create or replace function privado.exigir_admin() returns void
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not privado.es_admin() then
    raise exception 'No tenés permiso. Iniciá sesión con un usuario administrador.' using errcode = '42501';
  end if;
end $$;

revoke all on schema privado from public;
grant usage on schema privado to authenticated;
grant execute on function privado.es_admin() to authenticated;

do $$
declare t text;
begin
  foreach t in array array['admins','config','categorias','proveedores','productos','cajas','pedidos','ventas','compras','ajustes_stock'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists solo_admins on public.%I', t);
    execute format('create policy solo_admins on public.%I for all to authenticated using (privado.es_admin()) with check (privado.es_admin())', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
--  Ayudas internas
-- ---------------------------------------------------------------------
create or replace function privado.slug(t text) returns text
language sql immutable as $$
  select trim(both '-' from regexp_replace(
           translate(lower(coalesce(t, '')), 'áàäâãéèëêíìïîóòöôõúùüûñç', 'aaaaaeeeeiiiiooooouuuunc'),
           '[^a-z0-9]+', '-', 'g'));
$$;

create or replace function privado.ajustes() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select '{"stockNegativo": false, "verificarEdad": true, "pagos": ["Efectivo","Débito","Crédito","Transferencia","Mercado Pago"]}'::jsonb
         || coalesce((select ajustes from public.config where id = 1), '{}'::jsonb);
$$;

create or replace function privado.caja_json(c public.cajas) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  with v as (
    select pago, sum(total) t, count(*) n from public.ventas
    where caja_id = c.id and not anulada group by pago
  ), m as (
    select coalesce(sum((x->>'monto')::numeric) filter (where x->>'tipo' = 'ingreso'), 0) ing,
           coalesce(sum((x->>'monto')::numeric) filter (where x->>'tipo' = 'egreso'), 0) egr
    from jsonb_array_elements(c.movs) x
  )
  select to_jsonb(c) || jsonb_build_object(
    'por_pago', coalesce((select jsonb_object_agg(pago, t) from v), '{}'::jsonb),
    'total',    coalesce((select sum(t) from v), 0),
    'tickets',  coalesce((select sum(n) from v), 0),
    'ingresos', m.ing,
    'egresos',  m.egr,
    'efectivo', c.inicial + coalesce((select t from v where pago = 'Efectivo'), 0) + m.ing - m.egr)
  from m;
$$;

-- Crea una venta: descuenta stock con bloqueo, así dos cajas no venden la misma unidad.
create or replace function privado.crear_venta(p_lineas jsonb, p_desc_pct numeric, p_pago text,
  p_recibido numeric, p_pedido uuid, p_precios_fijos boolean) returns public.ventas
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  l jsonb; pr public.productos; v public.ventas;
  v_items jsonb := '[]'::jsonb; v_sub numeric := 0; v_desc numeric; v_caja uuid; v_precio numeric; v_cant int;
  v_neg boolean := coalesce((privado.ajustes() ->> 'stockNegativo')::boolean, false);
begin
  if coalesce(trim(p_pago), '') = '' then raise exception 'Elegí el medio de pago'; end if;
  if jsonb_typeof(p_lineas) is distinct from 'array' or jsonb_array_length(p_lineas) = 0 then
    raise exception 'No hay productos para vender';
  end if;
  select id into v_caja from public.cajas where cierre is null;
  if v_caja is null and p_pedido is null then raise exception 'Abrí la caja antes de vender'; end if;

  for l in select e from jsonb_array_elements(p_lineas) e order by e ->> 'id' loop
    v_cant := (l ->> 'cant')::int;
    if v_cant is null or v_cant <= 0 then raise exception 'Cantidad inválida'; end if;
    select * into pr from public.productos where id = l ->> 'id' for update;
    if not found then
      if p_precios_fijos then   -- producto borrado que estaba en un pedido: se cobra igual, sin stock
        v_precio := coalesce((l ->> 'precio')::numeric, 0);
        v_items := v_items || jsonb_build_object('id', l->>'id', 'nombre', l->>'nombre', 'categoria', null,
                                                 'cant', v_cant, 'precio', v_precio, 'costo', 0);
        v_sub := v_sub + v_precio * v_cant;
        continue;
      end if;
      raise exception 'Un producto del carrito ya no existe';
    end if;
    if not v_neg and pr.stock < v_cant then
      raise exception 'No hay stock suficiente de % (quedan %)', pr.nombre, pr.stock;
    end if;
    update public.productos set stock = stock - v_cant where id = pr.id;
    v_precio := case when p_precios_fijos then coalesce((l ->> 'precio')::numeric, pr.precio) else pr.precio end;
    v_items := v_items || jsonb_build_object('id', pr.id, 'nombre', pr.nombre, 'categoria', pr.categoria,
                                             'cant', v_cant, 'precio', v_precio, 'costo', pr.costo);
    v_sub := v_sub + v_precio * v_cant;
  end loop;

  v_desc := round(v_sub * least(100, greatest(0, coalesce(p_desc_pct, 0))) / 100, 2);
  if p_recibido is not null and p_recibido < v_sub - v_desc then raise exception 'El monto recibido no alcanza'; end if;
  insert into public.ventas (items, subtotal, descuento, total, pago, recibido, caja_id, pedido_id, usuario)
  values (v_items, v_sub, v_desc, v_sub - v_desc, p_pago, p_recibido, v_caja, p_pedido, auth.jwt() ->> 'email')
  returning * into v;
  return v;
end $$;

create or replace function privado.anular_venta(p_id uuid) returns public.ventas
language plpgsql security definer set search_path = public, pg_temp as $$
declare v public.ventas; i jsonb;
begin
  select * into v from public.ventas where id = p_id for update;
  if not found then raise exception 'La venta no existe'; end if;
  if v.anulada then raise exception 'La venta ya estaba anulada'; end if;
  for i in select * from jsonb_array_elements(v.items) loop
    update public.productos set stock = stock + (i ->> 'cant')::int where id = i ->> 'id';
  end loop;
  update public.ventas set anulada = true, anulada_en = now() where id = p_id returning * into v;
  return v;
end $$;

-- Arma las líneas de un pedido a partir de [{id, cant, precio?}]
create or replace function privado.lineas_pedido(p_items jsonb, p_solo_web boolean, p_permitir_precio boolean,
  out items jsonb, out total numeric, out completo boolean)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare r record;
begin
  items := '[]'::jsonb; total := 0; completo := true;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 40 then
    raise exception 'El pedido está vacío o tiene demasiados productos';
  end if;
  for r in
    select p.id, p.nombre, p.detalle,
           case when p_permitir_precio and (x ->> 'precio') is not null then (x ->> 'precio')::numeric else p.precio end as precio,
           least(greatest(coalesce((x ->> 'cant')::int, 0), 0), 99) as cant
    from jsonb_array_elements(p_items) with ordinality as e(x, n)
    join public.productos p on p.id = x ->> 'id'
    where not p_solo_web or (p.en_web and not p.solo_consulta)
    order by n
  loop
    continue when r.cant <= 0;
    items := items || jsonb_build_object('id', r.id, 'nombre', r.nombre, 'detalle', r.detalle, 'cant', r.cant, 'precio', r.precio);
    total := total + r.precio * r.cant;
    if r.precio <= 0 then completo := false; end if;
  end loop;
  if jsonb_array_length(items) = 0 then raise exception 'Ninguno de esos productos se puede pedir online'; end if;
end $$;

-- ---------------------------------------------------------------------
--  WEB PÚBLICA (cualquiera puede llamar estas dos)
-- ---------------------------------------------------------------------
create or replace function public.catalogo_web() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'negocio', coalesce((select negocio from public.config where id = 1), '{}'::jsonb),
    'categorias', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'nombre', c.nombre, 'tipo', c.tipo) order by c.orden, c.nombre)
      from public.categorias c
      where exists (select 1 from public.productos p where p.categoria = c.id and p.en_web)), '[]'::jsonb),
    'productos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', p.id, 'nombre', p.nombre, 'categoria', p.categoria, 'detalle', p.detalle,
               'precio', p.precio, 'stock', greatest(0, least(p.stock, 10)),
               'estrella', p.estrella, 'soloConsulta', p.solo_consulta, 'foto', p.foto)
             order by c.orden, p.orden, p.nombre)
      from public.productos p left join public.categorias c on c.id = p.categoria
      where p.en_web), '[]'::jsonb));
$$;

create or replace function public.crear_pedido(p_items jsonb, p_cliente text default '', p_entrega text default '', p_nota text default '')
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare l record; v_nro bigint;
begin
  if (select count(*) from public.pedidos where origen = 'web' and fecha > now() - interval '10 minutes') >= 30 then
    raise exception 'Estamos recibiendo muchos pedidos. Probá en unos minutos o escribinos por WhatsApp.';
  end if;
  select * into l from privado.lineas_pedido(p_items, true, false);
  insert into public.pedidos (origen, cliente, entrega, nota, items, total, precio_completo)
  values ('web', left(trim(coalesce(p_cliente, '')), 80), left(trim(coalesce(p_entrega, '')), 60),
          left(trim(coalesce(p_nota, '')), 300), l.items, l.total, l.completo)
  returning nro into v_nro;
  return jsonb_build_object('nro', v_nro, 'items', l.items, 'total', l.total, 'precio_completo', l.completo);
end $$;

-- ---------------------------------------------------------------------
--  PANEL (solo administradores)
-- ---------------------------------------------------------------------
create or replace function public.admin_datos() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform privado.exigir_admin();
  return jsonb_build_object(
    'email', auth.jwt() ->> 'email',
    'negocio', coalesce((select negocio from public.config where id = 1), '{}'::jsonb),
    'ajustes', privado.ajustes(),
    'categorias', coalesce((select jsonb_agg(to_jsonb(c) order by c.orden, c.nombre) from public.categorias c), '[]'::jsonb),
    'proveedores', coalesce((select jsonb_agg(to_jsonb(p) order by p.nombre) from public.proveedores p), '[]'::jsonb),
    'productos', coalesce((select jsonb_agg(to_jsonb(p) order by p.nombre) from public.productos p), '[]'::jsonb),
    'caja', (select privado.caja_json(c) from public.cajas c where c.cierre is null),
    'pendientes', (select count(*) from public.pedidos where estado = 'pendiente'),
    'ultimo_pedido', coalesce((select max(nro) from public.pedidos), 0));
end $$;

create or replace function public.admin_resumen() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform privado.exigir_admin();
  return jsonb_build_object(
    'pendientes', (select count(*) from public.pedidos where estado = 'pendiente'),
    'pagados', (select count(*) from public.pedidos where estado = 'pagado'),
    'ultimo_pedido', coalesce((select max(nro) from public.pedidos), 0));
end $$;

create or replace function public.admin_ventas(p_desde timestamptz, p_hasta timestamptz) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform privado.exigir_admin();
  return coalesce((select jsonb_agg(to_jsonb(v) order by v.fecha)
                   from (select * from public.ventas where fecha >= p_desde and fecha < p_hasta order by fecha desc limit 10000) v), '[]'::jsonb);
end $$;

create or replace function public.admin_pedidos(p_zona text default 'activos') returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform privado.exigir_admin();
  if p_zona = 'completados' then
    return coalesce((select jsonb_agg(to_jsonb(p) order by coalesce(p.entregado_en, p.cancelado_en, p.fecha) desc)
                     from (select * from public.pedidos where estado in ('entregado','cancelado')
                           order by coalesce(entregado_en, cancelado_en, fecha) desc limit 300) p), '[]'::jsonb);
  end if;
  return coalesce((select jsonb_agg(to_jsonb(p) order by p.nro)
                   from public.pedidos p where estado in ('pendiente','pagado')), '[]'::jsonb);
end $$;

create or replace function public.admin_cajas() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform privado.exigir_admin();
  return coalesce((select jsonb_agg(privado.caja_json(c) order by c.cierre desc)
                   from (select * from public.cajas where cierre is not null order by cierre desc limit 40) c), '[]'::jsonb);
end $$;

create or replace function public.admin_compras() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform privado.exigir_admin();
  return coalesce((select jsonb_agg(to_jsonb(c) || jsonb_build_object('proveedor', pv.nombre) order by c.fecha desc)
                   from (select * from public.compras order by fecha desc limit 150) c
                   left join public.proveedores pv on pv.id = c.proveedor_id), '[]'::jsonb);
end $$;

create or replace function public.admin_ajustes_stock() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform privado.exigir_admin();
  return coalesce((select jsonb_agg(to_jsonb(a) order by a.fecha desc)
                   from (select * from public.ajustes_stock order by fecha desc limit 40) a), '[]'::jsonb);
end $$;

-- Productos -----------------------------------------------------------
create or replace function public.guardar_producto(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id text := nullif(trim(p ->> 'id'), ''); v public.productos; base text;
begin
  perform privado.exigir_admin();
  if coalesce(trim(p ->> 'nombre'), '') = '' then raise exception 'El nombre es obligatorio'; end if;
  if v_id is null then
    base := coalesce(nullif(privado.slug(p ->> 'nombre'), ''), 'producto');
    v_id := base;
    while exists (select 1 from public.productos where id = v_id) loop
      v_id := base || '-' || substr(md5(random()::text), 1, 4);
    end loop;
    insert into public.productos (id, codigo, nombre, detalle, categoria, proveedor_id, costo, precio, stock, stock_min,
                                  en_web, estrella, solo_consulta, foto, orden)
    values (v_id, nullif(trim(p ->> 'codigo'), ''), trim(p ->> 'nombre'), coalesce(trim(p ->> 'detalle'), ''),
            nullif(p ->> 'categoria', ''), nullif(p ->> 'proveedor_id', '')::uuid,
            coalesce((p ->> 'costo')::numeric, 0), coalesce((p ->> 'precio')::numeric, 0),
            coalesce((p ->> 'stock')::int, 0), coalesce((p ->> 'stock_min')::int, 0),
            coalesce((p ->> 'en_web')::boolean, true), coalesce((p ->> 'estrella')::boolean, false),
            coalesce((p ->> 'solo_consulta')::boolean, false), coalesce(p ->> 'foto', ''), coalesce((p ->> 'orden')::int, 0))
    returning * into v;
  else
    update public.productos set
      codigo = nullif(trim(p ->> 'codigo'), ''), nombre = trim(p ->> 'nombre'), detalle = coalesce(trim(p ->> 'detalle'), ''),
      categoria = nullif(p ->> 'categoria', ''), proveedor_id = nullif(p ->> 'proveedor_id', '')::uuid,
      costo = coalesce((p ->> 'costo')::numeric, 0), precio = coalesce((p ->> 'precio')::numeric, 0),
      stock_min = coalesce((p ->> 'stock_min')::int, 0),
      en_web = coalesce((p ->> 'en_web')::boolean, true), estrella = coalesce((p ->> 'estrella')::boolean, false),
      solo_consulta = coalesce((p ->> 'solo_consulta')::boolean, false), foto = coalesce(p ->> 'foto', ''),
      orden = coalesce((p ->> 'orden')::int, 0), actualizado = now()
    where id = v_id returning * into v;
    if not found then raise exception 'El producto no existe'; end if;
  end if;
  return to_jsonb(v);
exception when unique_violation then
  raise exception 'Ya hay otro producto con ese código de barras';
end $$;

create or replace function public.borrar_producto(p_id text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.exigir_admin();
  delete from public.productos where id = p_id;
end $$;

create or replace function public.ajustar_stock(p_id text, p_tipo text, p_cant int, p_motivo text default '') returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare pr public.productos; v_antes int; v_nuevo int;
begin
  perform privado.exigir_admin();
  if p_cant is null or p_cant < 0 then raise exception 'Cantidad inválida'; end if;
  select * into pr from public.productos where id = p_id for update;
  if not found then raise exception 'El producto no existe'; end if;
  v_antes := pr.stock;
  v_nuevo := case p_tipo when 'sumar' then v_antes + p_cant when 'restar' then v_antes - p_cant when 'fijar' then p_cant end;
  if v_nuevo is null then raise exception 'Tipo de ajuste inválido'; end if;
  update public.productos set stock = v_nuevo, actualizado = now() where id = p_id returning * into pr;
  insert into public.ajustes_stock (producto_id, nombre, antes, despues, motivo, usuario)
  values (p_id, pr.nombre, v_antes, v_nuevo, coalesce(p_motivo, ''), auth.jwt() ->> 'email');
  return to_jsonb(pr);
end $$;

create or replace function public.actualizar_precios(p_categoria text, p_proveedor uuid, p_pct numeric, p_redondeo int, p_costo boolean)
returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare n int; r int := greatest(1, coalesce(p_redondeo, 1));
begin
  perform privado.exigir_admin();
  if coalesce(p_pct, 0) = 0 then raise exception 'Ingresá un porcentaje'; end if;
  update public.productos set
    precio = greatest(r, round(precio * (1 + p_pct / 100) / r) * r),
    costo = case when p_costo then round(costo * (1 + p_pct / 100), 2) else costo end,
    actualizado = now()
  where precio > 0 and (p_categoria is null or categoria = p_categoria) and (p_proveedor is null or proveedor_id = p_proveedor);
  get diagnostics n = row_count;
  return n;
end $$;

-- Proveedores y categorías ---------------------------------------------
create or replace function public.guardar_proveedor(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v public.proveedores;
begin
  perform privado.exigir_admin();
  if coalesce(trim(p ->> 'nombre'), '') = '' then raise exception 'El nombre es obligatorio'; end if;
  if nullif(p ->> 'id', '') is null then
    insert into public.proveedores (nombre, contacto, telefono, email, notas)
    values (trim(p ->> 'nombre'), coalesce(trim(p ->> 'contacto'), ''), coalesce(trim(p ->> 'telefono'), ''),
            coalesce(trim(p ->> 'email'), ''), coalesce(trim(p ->> 'notas'), ''))
    returning * into v;
  else
    update public.proveedores set nombre = trim(p ->> 'nombre'), contacto = coalesce(trim(p ->> 'contacto'), ''),
      telefono = coalesce(trim(p ->> 'telefono'), ''), email = coalesce(trim(p ->> 'email'), ''), notas = coalesce(trim(p ->> 'notas'), '')
    where id = (p ->> 'id')::uuid returning * into v;
  end if;
  return to_jsonb(v);
end $$;

create or replace function public.borrar_proveedor(p_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.exigir_admin();
  delete from public.proveedores where id = p_id;
end $$;

create or replace function public.guardar_categoria(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v public.categorias; v_id text := nullif(trim(p ->> 'id'), ''); base text;
begin
  perform privado.exigir_admin();
  if coalesce(trim(p ->> 'nombre'), '') = '' then raise exception 'El nombre es obligatorio'; end if;
  if v_id is null or not exists (select 1 from public.categorias where id = v_id) then
    base := coalesce(nullif(privado.slug(p ->> 'nombre'), ''), 'categoria');
    v_id := base;
    while exists (select 1 from public.categorias where id = v_id) loop v_id := base || '-' || substr(md5(random()::text), 1, 3); end loop;
    insert into public.categorias (id, nombre, tipo, orden, restringida)
    values (v_id, trim(p ->> 'nombre'), coalesce(nullif(p ->> 'tipo', ''), 'botella'), coalesce((p ->> 'orden')::int, 0),
            coalesce((p ->> 'restringida')::boolean, false))
    returning * into v;
  else
    update public.categorias set nombre = trim(p ->> 'nombre'), tipo = coalesce(nullif(p ->> 'tipo', ''), 'botella'),
      orden = coalesce((p ->> 'orden')::int, 0), restringida = coalesce((p ->> 'restringida')::boolean, false)
    where id = v_id returning * into v;
  end if;
  return to_jsonb(v);
end $$;

create or replace function public.borrar_categoria(p_id text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  perform privado.exigir_admin();
  select count(*) into n from public.productos where categoria = p_id;
  if n > 0 then raise exception 'La categoría tiene % productos. Pasalos a otra categoría antes de borrarla.', n; end if;
  delete from public.categorias where id = p_id;
end $$;

-- Configuración y usuarios ---------------------------------------------
create or replace function public.guardar_negocio(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.exigir_admin();
  insert into public.config (id, negocio) values (1, p) on conflict (id) do update set negocio = excluded.negocio;
  return p;
end $$;

create or replace function public.guardar_ajustes(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.exigir_admin();
  insert into public.config (id, ajustes) values (1, p) on conflict (id) do update set ajustes = excluded.ajustes;
  return privado.ajustes();
end $$;

create or replace function public.admin_usuarios() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform privado.exigir_admin();
  return coalesce((select jsonb_agg(email order by creado) from public.admins), '[]'::jsonb);
end $$;

create or replace function public.agregar_admin(p_email text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.exigir_admin();
  if coalesce(p_email, '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Email inválido'; end if;
  insert into public.admins (email) values (lower(trim(p_email))) on conflict do nothing;
end $$;

create or replace function public.quitar_admin(p_email text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.exigir_admin();
  if lower(p_email) = lower(auth.jwt() ->> 'email') then raise exception 'No podés quitarte a vos mismo'; end if;
  delete from public.admins where lower(email) = lower(p_email);
end $$;

-- Ventas -----------------------------------------------------------------
create or replace function public.registrar_venta(p_items jsonb, p_descuento numeric default 0, p_pago text default 'Efectivo',
  p_recibido numeric default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.exigir_admin();
  return to_jsonb(privado.crear_venta(p_items, p_descuento, p_pago, p_recibido, null, false));
end $$;

create or replace function public.anular_venta(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v public.ventas;
begin
  perform privado.exigir_admin();
  v := privado.anular_venta(p_id);
  if v.pedido_id is not null then
    update public.pedidos set estado = 'pendiente', pago = null, pagado_en = null, venta_id = null
      where id = v.pedido_id and estado = 'pagado';
    update public.pedidos set estado = 'cancelado', cancelado_en = now()
      where id = v.pedido_id and estado = 'entregado';
  end if;
  return to_jsonb(v);
end $$;

-- Ingresos de mercadería -----------------------------------------------
create or replace function public.registrar_compra(p_proveedor uuid, p_comprobante text, p_items jsonb, p_actualizar_costo boolean)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare i jsonb; pr public.productos; v_items jsonb := '[]'::jsonb; v_total numeric := 0; v_cant int; v_costo numeric; c public.compras;
begin
  perform privado.exigir_admin();
  for i in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    v_cant := coalesce((i ->> 'cant')::int, 0); v_costo := coalesce((i ->> 'costo')::numeric, 0);
    continue when v_cant <= 0;
    update public.productos set stock = stock + v_cant,
           costo = case when p_actualizar_costo and v_costo > 0 then v_costo else costo end, actualizado = now()
     where id = i ->> 'id' returning * into pr;
    continue when not found;
    v_items := v_items || jsonb_build_object('id', pr.id, 'nombre', pr.nombre, 'cant', v_cant, 'costo', v_costo);
    v_total := v_total + v_cant * v_costo;
  end loop;
  if jsonb_array_length(v_items) = 0 then raise exception 'Agregá al menos un producto con cantidad'; end if;
  insert into public.compras (proveedor_id, comprobante, items, total, usuario)
  values (p_proveedor, coalesce(trim(p_comprobante), ''), v_items, v_total, auth.jwt() ->> 'email') returning * into c;
  return to_jsonb(c);
end $$;

-- Caja -------------------------------------------------------------------
create or replace function public.abrir_caja(p_inicial numeric) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.cajas;
begin
  perform privado.exigir_admin();
  if exists (select 1 from public.cajas where cierre is null) then raise exception 'La caja ya está abierta'; end if;
  insert into public.cajas (inicial, usuario) values (coalesce(p_inicial, 0), auth.jwt() ->> 'email') returning * into c;
  return privado.caja_json(c);
end $$;

create or replace function public.movimiento_caja(p_tipo text, p_monto numeric, p_desc text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.cajas;
begin
  perform privado.exigir_admin();
  if p_tipo not in ('ingreso','egreso') then raise exception 'Tipo inválido'; end if;
  if coalesce(p_monto, 0) <= 0 then raise exception 'Monto inválido'; end if;
  update public.cajas set movs = movs || jsonb_build_array(jsonb_build_object('fecha', now(), 'tipo', p_tipo, 'monto', p_monto,
         'desc', coalesce(trim(p_desc), ''), 'usuario', auth.jwt() ->> 'email'))
   where cierre is null returning * into c;
  if not found then raise exception 'La caja está cerrada'; end if;
  return privado.caja_json(c);
end $$;

create or replace function public.cerrar_caja(p_contado numeric) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.cajas; v_esp numeric;
begin
  perform privado.exigir_admin();
  select * into c from public.cajas where cierre is null for update;
  if not found then raise exception 'La caja ya está cerrada'; end if;
  v_esp := (privado.caja_json(c) ->> 'efectivo')::numeric;
  update public.cajas set cierre = now(), esperado = v_esp, contado = coalesce(p_contado, 0), diferencia = coalesce(p_contado, 0) - v_esp
   where id = c.id returning * into c;
  return privado.caja_json(c);
end $$;

-- Pedidos ----------------------------------------------------------------
create or replace function public.admin_guardar_pedido(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare l record; v public.pedidos; v_id uuid := nullif(p ->> 'id', '')::uuid;
begin
  perform privado.exigir_admin();
  select * into l from privado.lineas_pedido(p -> 'items', false, true);
  if v_id is null then
    insert into public.pedidos (origen, cliente, telefono, entrega, nota, items, total, precio_completo)
    values (coalesce(nullif(p ->> 'origen', ''), 'whatsapp'), coalesce(trim(p ->> 'cliente'), ''), coalesce(trim(p ->> 'telefono'), ''),
            coalesce(p ->> 'entrega', ''), coalesce(trim(p ->> 'nota'), ''), l.items, l.total, l.completo)
    returning * into v;
  else
    update public.pedidos set cliente = coalesce(trim(p ->> 'cliente'), ''), telefono = coalesce(trim(p ->> 'telefono'), ''),
      entrega = coalesce(p ->> 'entrega', ''), nota = coalesce(trim(p ->> 'nota'), ''), items = l.items, total = l.total,
      precio_completo = l.completo
    where id = v_id and estado = 'pendiente' returning * into v;
    if not found then raise exception 'Solo se pueden editar pedidos que todavía no se cobraron'; end if;
  end if;
  return to_jsonb(v);
end $$;

create or replace function public.pedido_estado(p_id uuid, p_estado text, p_pago text default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v public.pedidos; vt public.ventas; de text; a text := p_estado;
begin
  perform privado.exigir_admin();
  select * into v from public.pedidos where id = p_id for update;
  if not found then raise exception 'El pedido no existe'; end if;
  de := v.estado;

  if de = 'pendiente' and a in ('pagado','entregado') then
    if exists (select 1 from jsonb_array_elements(v.items) i where coalesce((i ->> 'precio')::numeric, 0) <= 0) then
      raise exception 'Hay productos sin precio en el pedido. Editalo y cargá los precios antes de cobrarlo.';
    end if;
    vt := privado.crear_venta(v.items, 0, p_pago, null, v.id, true);
    update public.pedidos set estado = a, pago = p_pago, pagado_en = now(), venta_id = vt.id,
           entregado_en = case when a = 'entregado' then now() end
     where id = p_id returning * into v;
  elsif de = 'pagado' and a = 'entregado' then
    update public.pedidos set estado = 'entregado', entregado_en = now() where id = p_id returning * into v;
  elsif de = 'entregado' and a = 'pagado' then
    update public.pedidos set estado = 'pagado', entregado_en = null where id = p_id returning * into v;
  elsif de in ('pagado','entregado') and a in ('pendiente','cancelado') then
    if v.venta_id is not null and exists (select 1 from public.ventas where id = v.venta_id and not anulada) then
      perform privado.anular_venta(v.venta_id);
    end if;
    update public.pedidos set estado = a, pago = null, pagado_en = null, entregado_en = null, venta_id = null,
           cancelado_en = case when a = 'cancelado' then now() end
     where id = p_id returning * into v;
  elsif de = 'pendiente' and a = 'cancelado' then
    update public.pedidos set estado = 'cancelado', cancelado_en = now() where id = p_id returning * into v;
  elsif de = 'cancelado' and a = 'pendiente' then
    update public.pedidos set estado = 'pendiente', cancelado_en = null where id = p_id returning * into v;
  else
    raise exception 'No se puede pasar un pedido de "%" a "%"', de, a;
  end if;
  return to_jsonb(v);
end $$;

create or replace function public.admin_respaldo() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform privado.exigir_admin();
  return jsonb_build_object(
    'fecha', now(),
    'config', (select to_jsonb(c) from public.config c where id = 1),
    'categorias', (select jsonb_agg(to_jsonb(x)) from public.categorias x),
    'proveedores', (select jsonb_agg(to_jsonb(x)) from public.proveedores x),
    'productos', (select jsonb_agg(to_jsonb(x)) from public.productos x),
    'pedidos', (select jsonb_agg(to_jsonb(x)) from public.pedidos x),
    'ventas', (select jsonb_agg(to_jsonb(x)) from public.ventas x),
    'compras', (select jsonb_agg(to_jsonb(x)) from public.compras x),
    'cajas', (select jsonb_agg(to_jsonb(x)) from public.cajas x),
    'ajustes_stock', (select jsonb_agg(to_jsonb(x)) from public.ajustes_stock x));
end $$;

-- Quién puede llamar qué -------------------------------------------------
do $$
declare f record;
begin
  -- funciones internas: nadie de afuera
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'privado' and p.proname <> 'es_admin' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
  -- funciones del panel: solo usuarios con sesión (y adentro se chequea que sea admin)
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in (
             'admin_datos','admin_resumen','admin_ventas','admin_pedidos','admin_cajas','admin_compras','admin_ajustes_stock',
             'guardar_producto','borrar_producto','ajustar_stock','actualizar_precios','guardar_proveedor','borrar_proveedor',
             'guardar_categoria','borrar_categoria','guardar_negocio','guardar_ajustes','admin_usuarios','agregar_admin','quitar_admin',
             'registrar_venta','anular_venta','registrar_compra','abrir_caja','movimiento_caja','cerrar_caja',
             'admin_guardar_pedido','pedido_estado','admin_respaldo') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
grant execute on function public.catalogo_web() to anon, authenticated;
grant execute on function public.crear_pedido(jsonb, text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
--  Fotos de productos (Supabase Storage, carpeta pública "fotos")
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('fotos', 'fotos', true)
on conflict (id) do update set public = true;

drop policy if exists fotos_admin_leer on storage.objects;
drop policy if exists fotos_admin_subir on storage.objects;
drop policy if exists fotos_admin_cambiar on storage.objects;
drop policy if exists fotos_admin_borrar on storage.objects;
create policy fotos_admin_leer on storage.objects for select to authenticated using (bucket_id = 'fotos' and privado.es_admin());
create policy fotos_admin_subir on storage.objects for insert to authenticated with check (bucket_id = 'fotos' and privado.es_admin());
create policy fotos_admin_cambiar on storage.objects for update to authenticated using (bucket_id = 'fotos' and privado.es_admin());
create policy fotos_admin_borrar on storage.objects for delete to authenticated using (bucket_id = 'fotos' and privado.es_admin());

-- =====================================================================
--  Datos iniciales (solo se cargan si todavía no existen)
-- =====================================================================
insert into public.admins (email) values ('toto.telleria@gmail.com') on conflict do nothing;
insert into public.config (id, negocio, ajustes) values (1, '{"nombre": "Amero", "bajada": "Tabaquería", "direccion": "Rawson 2015, Martínez", "mapa": "https://goo.gl/maps/tmrPE3364oyp4G8f6", "telefono": "4792-9634", "email": "info@ameroshop.com.ar", "whatsapp": "", "instagram": "tabaqueria.amero", "horario": "", "aviso": "", "historia": "En Amero elegimos cada habano, cada whisky y cada pipa como si fuera para nosotros. Te asesoramos para encontrar el tabaco justo, el regalo indicado o la botella para una ocasión especial.\n\nVení a conocernos en Martínez o armá tu pedido online."}'::jsonb, '{}'::jsonb) on conflict (id) do nothing;
insert into public.categorias (id, nombre, tipo, orden, restringida) values
  ('habanos', 'Habanos', 'habano', 0, true),
  ('whisky', 'Whisky', 'botella', 10, true),
  ('pipas', 'Pipas', 'pipa', 20, false),
  ('tabacos', 'Tabacos', 'lata', 30, true),
  ('licores', 'Licores y destilados', 'botella', 40, true),
  ('accesorios', 'Accesorios', 'encendedor', 50, false)
on conflict (id) do nothing;
insert into public.productos (id, nombre, detalle, categoria, precio, stock, estrella, solo_consulta, foto, orden) values
  ('cohiba-siglo-vi', 'Cohiba Siglo VI', 'Caja x 10', 'habanos', 0, 0, true, true, '', 0),
  ('cohiba-robustos', 'Cohiba Robustos', 'Unidad', 'habanos', 0, 0, false, true, '', 10),
  ('montecristo-club', 'Montecristo Club', 'Lata x 10', 'habanos', 0, 0, false, true, '', 20),
  ('partagas-serie-club', 'Partagás Serie Club', 'Lata x 10', 'habanos', 0, 0, false, true, '', 30),
  ('trinidad-coloniales', 'Trinidad Coloniales', 'Unidad', 'habanos', 0, 0, false, true, '', 40),
  ('romeo-julieta-mini', 'Romeo y Julieta Mini', 'Lata x 20', 'habanos', 0, 0, false, true, '', 50),
  ('macallan-12-double-cask', 'The Macallan 12 Double Cask', '700 ml', 'whisky', 0, 0, true, false, '', 60),
  ('talisker-10', 'Talisker 10 años', '750 ml', 'whisky', 0, 0, true, false, '', 70),
  ('caol-ila-12', 'Caol Ila 12 años', '750 ml', 'whisky', 0, 4, false, false, '', 80),
  ('jw-platinum', 'Johnnie Walker Platinum Label', '750 ml', 'whisky', 0, 0, false, false, '', 90),
  ('jameson-black-barrel', 'Jameson Black Barrel', '750 ml', 'whisky', 0, 3, false, false, '', 100),
  ('monkey-shoulder', 'Monkey Shoulder', '700 ml', 'whisky', 0, 0, false, false, '', 110),
  ('pipa-billiard-brezo', 'Pipa Billiard de brezo', 'Curva, filtro 9 mm', 'pipas', 0, 0, true, false, '', 120),
  ('pipa-dublin', 'Pipa Dublin', 'Recta, terminación arenada', 'pipas', 0, 0, false, false, '', 130),
  ('tabaco-pipa-aromatico', 'Tabaco para pipa aromático', 'Lata 50 g', 'tabacos', 0, 0, true, true, '', 140),
  ('tabaco-armar-virginia', 'Tabaco para armar Virginia', 'Pouch 30 g', 'tabacos', 0, 0, false, true, '', 150),
  ('jagermeister-cold', 'Jägermeister Cold Macerated', '100 ml', 'licores', 0, 8, false, false, '', 160),
  ('licor-cafe', 'Licor de café', '700 ml', 'licores', 0, 0, false, false, '', 170),
  ('encendedor-jet', 'Encendedor jet para habanos', 'Llama doble', 'accesorios', 0, 0, true, false, '', 180),
  ('cortapuros', 'Cortapuros doble hoja', 'Acero inoxidable', 'accesorios', 0, 0, false, false, '', 190),
  ('humidor-25', 'Humidor de cedro', 'Para 25 habanos', 'accesorios', 0, 0, false, false, '', 200)
on conflict (id) do nothing;
