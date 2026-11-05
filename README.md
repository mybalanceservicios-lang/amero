# Amero · Tabaquería (web)

Web pública de Tabaquería Amero (Rawson 2015, Martínez). El cliente arma el pedido y lo manda por WhatsApp, igual que en Aramé.

## Archivos

- `index.html`: la web. Portada con la pipa: al bajar, sale humo y aparecen los productos estrella.
- `fotos/`: logo (`logo-amero.png` en crema para fondo oscuro, `logo-amero-negro.png` original), íconos de la pestaña, fotos de productos (`<id>.jpg`) y de portada.
- `catalogo.json`: datos del local, categorías y productos. Es lo que se edita para cambiar la web.

## Cómo cargar productos (`catalogo.json`)

Cada producto tiene:

| Campo | Qué es |
|---|---|
| `nombre`, `detalle` | Nombre y presentación (ej. `700 ml`, `Caja x 10`). |
| `categoria` | Uno de los `id` de `categorias`. |
| `precio` | En pesos. Si es `0` se muestra "Precio a confirmar". **Los precios cargados hoy son inventados, para ver cómo queda.** |
| `stock` | Opcional. Con 5 o menos muestra "Quedan N"; con 0, "Sin stock". |
| `estrella` | `true` para que salga en el humo de la portada (se usan los primeros 6). |
| `descripcion` | Texto que aparece en la ficha cuando tocan la foto. |
| `ficha` | Características de la ficha, como lista de pares: `[["Origen","Cuba"],["Medidas","150 mm · cepo 52"]]`. |
| `foto` | Ruta de la foto (ej. `fotos/macallan-12.jpg`). Si está vacío se usa un dibujo provisorio. |

En `negocio` falta completar `whatsapp` (con código de país, ej. `5491112345678`), `horario` y `youtube` (link completo al canal; si está vacío no se muestra el botón). En `retiro` van el horario desde/hasta para los turnos de retiro que se ofrecen en el carrito.

## Pendiente

- Fotos del local y de los productos que todavía usan dibujo provisorio (pipas, tabacos, licor de café y accesorios). El logo y 13 fotos de productos se tomaron de ameroshop.com.ar y están en `fotos/`.
- Precios reales y lista final de productos estrella.
- Texto de "Nuestra historia" (el actual es provisorio).
- Conexión con el sistema de stock que arma el socio: la idea es que la web lea productos y stock de la misma base y que cada pedido descuente stock.

## Probar en la compu

```
python -m http.server 5173
```

y abrir http://localhost:5173 (abrir el `index.html` con doble clic no carga el catálogo).

## Publicar

GitHub → Settings → Pages → Deploy from a branch → `main` / root. Queda en `https://mybalanceservicios-lang.github.io/amero/`.
