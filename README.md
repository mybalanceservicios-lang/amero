# Amero · Tabaquería (web + sistema de gestión)

Web pública de Tabaquería Amero (Rawson 2015, Martínez) y panel interno para manejar el local. Los dos usan la misma base de datos (Supabase): productos, precios y stock son uno solo, y los pedidos que hacen los clientes en la web le aparecen al dueño en el panel.

## Archivos

| Archivo | Qué es |
|---|---|
| `index.html` | La web. El cliente arma el pedido y lo manda por WhatsApp; el pedido queda registrado con un número (#12). |
| `admin/index.html` | El panel (`/admin`): pedidos, ventas en el local, productos y stock, ingresos de mercadería, proveedores, caja, historial, reportes y edición de la web. |
| `config.js` | Dirección y clave pública de Supabase. La usan la web y el panel. |
| `supabase/instalar.sql` | Crea toda la base de datos con los permisos. Se puede volver a correr sin perder datos. |
| `catalogo.json` | Catálogo de respaldo: la web lo usa solo si la base no responde. |

## Puesta en marcha (una sola vez)

1. **Crear la base:** en Supabase → *SQL Editor* → *New query*, pegar todo `supabase/instalar.sql` y tocar *Run*. Carga las categorías y productos actuales y deja a `toto.telleria@gmail.com` como administrador.
2. **Crear el usuario del dueño:** *Authentication* → *Users* → *Add user* → *Create new user*, con el email `toto.telleria@gmail.com`, una contraseña y la opción *Auto Confirm User* tildada.
3. **Link de los mails:** *Authentication* → *URL Configuration* → *Site URL*: `https://mybalanceservicios-lang.github.io/amero/admin/` (para que "Olvidé mi contraseña" vuelva al panel).
4. **Entrar al panel** en `/admin`, ir a **Web** y cargar el WhatsApp del local (ej. `5491112345678`) y el horario.
5. **Cargar precios y stock** en **Productos** (botón *Stock*) o con **Ingresos**. Mientras un producto tenga stock 0, la web lo muestra como "Sin stock".

Para sumar a alguien más: **Ajustes** → *Usuarios con acceso* → agregar su email, y crearle el usuario como en el paso 2 (o que entre con "Primera vez: crear contraseña").

## Cómo funcionan los pedidos

1. El cliente arma el pedido en la web y toca *Enviar por WhatsApp*: el pedido se guarda con un número y se abre WhatsApp con el mensaje (que incluye ese número).
2. En el panel, **Pedidos** → *Nuevos · por cobrar*. El panel avisa con un sonido y un número en rojo cuando entra uno (revisa cada 20 segundos).
3. **Cobrado →**: se elige el medio de pago, se registra la venta y se descuenta el stock. El pedido pasa a *Pagados · por entregar*.
4. **Entregado ✓**: pasa a **Completados**, así no se acumulan en la pantalla principal.
5. Si algo se tocó por error: *↩ No pagó* (anula el cobro y devuelve el stock) o *Reabrir* desde Completados.

Los pedidos que llegan por teléfono o directo al WhatsApp se cargan con **+ Cargar pedido**. Si un producto no tiene precio (precio 0, "a confirmar"), hay que editar el pedido y poner el precio antes de cobrarlo.

## Seguridad

- La web solo puede leer el catálogo (sin costos ni proveedores) y crear pedidos. Todo lo demás lo hacen funciones de la base que verifican que el usuario esté en la lista de administradores.
- La clave de `config.js` es la *publishable*: es pública a propósito. **Nunca** poner la *secret key* en estos archivos.
- Las ventas y los pedidos descuentan stock dentro de la base, así no se vende dos veces la misma unidad aunque usen el panel desde la compu y el celular a la vez.

## Probar en la compu

```
python -m http.server 5173
```

y abrir http://localhost:5173 (la web) o http://localhost:5173/admin/ (el panel).

## Publicar

GitHub → Settings → Pages → Deploy from a branch → `main` / root. Queda en `https://mybalanceservicios-lang.github.io/amero/` y el panel en `https://mybalanceservicios-lang.github.io/amero/admin/`.

## Pendiente

- Logo, fotos de productos y del local (las fotos ya se pueden subir desde el panel).
- Precios reales, stock y lista final de productos destacados.
- Texto de "Nuestra historia" (se edita en el panel → Web).
