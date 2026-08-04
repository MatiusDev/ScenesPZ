# Qué probar ahora

Una sola página. Se reescribe cada vez que una etapa abre o cierra. Si esta página y
cualquier otra se contradicen, ésta es la que está vieja — arreglala.

> **Nota de idioma.** Este archivo va en español porque es el que vos usás mientras jugás.
> Todo el resto — código, comentarios, planes, commits — sigue en inglés.

Hoja de ruta completa: [`docs/plans/README.md`](plans/README.md).

---

## Lo que salió de la corrida anterior

**Encontré el fallo que se repetía, y era mío.** 511 excepciones idénticas, una por frame:

```
java.lang.RuntimeException: Object tried to call nil in setTextureColor
  Lua(Vanilla).setTextureColor(ISButton.lua:184)
  Lua((MOD:ScenesPZ Relations)).prerender(ScenesRelationsSidebar.lua:100)
```

`getTexture("media/ui/emotes/stop.png")` devolvía `nil`. Esa ruta aparece tal cual en el
Lua de vanilla, pero el PNG no se resuelve acá — que una cadena esté en un archivo del
juego no significa que el recurso exista. Botón sin textura, `setTextureColor` explota.

Y `pcall` no salvó nada: atrapa el error de Lua, pero **el motor loguea la excepción de
Java igual**. Por eso el log de 3 MB era casi solo eso, y las líneas `ready` quedaron
sepultadas.

---

## Lo que cambió ahora

**Rueda propia, dibujada por nosotros.** `ISRadialMenu` no era un problema de estilo: el
lado Java es dueño del dibujo y solo pinta el texto de un gajo cuando el cursor ya está
encima. Por eso volvía a lo mismo hicieras lo que hicieras.

Ahora cada opción es una **tarjeta con texto** puesta sobre un círculo. Nosotros las
colocamos, así que sabemos exactamente dónde están — se acabó el cálculo de ángulos.

**Dos niveles.** Al pasar el cursor por **Talk** se abre un segundo anillo:

| Pregunta | Responde con |
|---|---|
| Who are you? | nombre y si pertenece a un grupo |
| What are you doing? | su programa en palabras, *"I'm holding this place."* |
| How are you holding up? | su salud en bandas, no en números |
| What are you like? | **no construido** — necesita la etapa de rasgos |

Volver al centro sale del submenú. Las cuatro preguntas cuentan como **una sola
conversación**: el descanso se comprueba una vez, así que preguntar cuatro cosas seguidas
no da 16 puntos.

**Lo no construido lo dice.** `Trade` está en la rueda y contesta *"I can't do that yet -
trading"* en texto flotante. Igual `What are you like?`. Todo pasa por una única función
`SR.Wheel.NotYet`, así que cuando algo se construya hay un solo lugar que borrar.

**Los botones de la barra izquierda ya no usan texturas.** Ahora son botones de texto con
fondo: **SAFE** en verde cuando la protección está activa, **HIT** en rojo cuando no. Todo
lo que hace ese código ahora es asignar tablas de Lua — no puede reventar.

**Reglas de revisión.** Creé `docs/CODE-REVIEW-RULES.md` con once reglas, cada una escrita
a partir de un bug real que costó una sesión, y el agente revisor `pz-review` que las
aplica. Las apliqué a este código antes de commitear: los siete identificadores nuevos
(`drawRectBorder`, `drawTextCentre`, `UIFont.Medium`, `getMouseX`, `ISPanel:derive`,
`addToUIManager`, `getPlayerScreenLeft`) tienen callsite verificado en vanilla.

---

## Antes de empezar

```bash
tools/sync-mods.sh
```

---

## Las pruebas, en orden

### 1. Se acabaron las excepciones

**Hacé:** entrá, jugá dos minutos, salí y buscá en `console.txt` la palabra
`setTextureColor`.

**Pasa si** no aparece **ninguna vez**. Antes salía 511.

Y confirmá que estén las seis líneas de arranque:

```
SREL| STORE ready      SREL| GUARD ready
SREL| WHEEL ready      SREL| MEMTEST ready
SREL| PANEL ready      SREL| SIDEBAR ready
```

---

### 2. La rueda, ahora con texto

**Hacé:** mantené **V** cerca de alguien.

**Pasa si:**
- Ves **tarjetas con el nombre de cada acción escrito adentro**: `Talk`, `Trade`,
  `Follow me`. Sin pasar el cursor por encima.
- En el centro está el nombre del sobreviviente. Sin número de confianza.
- La tarjeta bajo el cursor se ilumina en verde.
- `Trade` se ve en rojo apagado con `(not built)` debajo.

---

### 3. El submenú de conversación

**Hacé:** con la rueda abierta, **poné el cursor sobre Talk**.

**Pasa si:**
- El anillo se reemplaza por las cuatro preguntas.
- En el centro aparece `< back`.
- Mové el cursor al centro y vuelve al anillo principal.
- Soltá **V** sobre una pregunta y la respuesta sale como texto flotante sobre vos.
- `What are you like?` sale gris con `(traits not built)` y contesta *"I can't do that
  yet"*.

---

### 4. Los botones de la barra izquierda

**Hacé:** mirá debajo del corazón.

**Pasa si** hay dos botones con texto: **SAFE** (verde) y **WHO**. Clic en SAFE lo pone en
**HIT** rojo. Clic en WHO abre el panel de relaciones.

---

### 5. El escudo — sigue pendiente de la corrida anterior

Con un aliado al lado, pegale a propósito. **Mirá si le baja la vida.** Y buscá en el log:

```
GUARD setInvincible is not available on IsoZombie
```

Si aparece, la invulnerabilidad tampoco funciona sobre NPC.

---

### 6. El test de memoria — sigue pendiente

En la consola, dos veces:

```lua
ScenesRelations.MemTest()
```

Entre una y otra, esperá a que las líneas `PROBE sweep` dejen de nombrar a esa persona. El
log da el veredicto: `PASS`, `PARTIAL` o `FAIL`.

---

### 7. ¿El motor mueve las emociones de un NPC?

Buscá las líneas `PROBE tick` — sale una por barrido:

```
SREL| PROBE tick | Luca Cruz | panic=0.000 stress=0.000 thirst=0.100 ...
```

**Lo que importa no es el valor, es si cambia entre barridos.** Si queda clavado toda la
sesión, hay que simular las emociones. Si se mueve solo, media etapa 06 desaparece.

---

## Qué mandarme

`console.txt` y una línea por prueba. De la 5, si le bajó la vida. De la 7, dos líneas
`PROBE tick` separadas en el tiempo para poder compararlas.

---

## En qué estamos

| Etapa | Estado |
|---|---|
| [00 — Mundo de pruebas](plans/00-test-world.md) | construida, confirmada a medias |
| [01 — Memoria durable](plans/01-durable-memory.md) | construida, **sin confirmar** |
| [02 — Rueda de interacción](plans/02-interaction-wheel.md) | rueda aprobada; panel a rediseñar; escudo y barra lateral sin probar |

Sigue: [03 — Vida propia](plans/03-idle-life.md) — que recojan cosas, se las pongan y
looteen donde viven.
