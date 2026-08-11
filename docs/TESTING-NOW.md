# ► Probá esto

**Esta página se REESCRIBE entera cada corrida.** No se le agrega nada. Lo que se cierra se
muda a [`docs/TEST-LOG.md`](TEST-LOG.md) y desaparece de acá.

> Español porque lo leés con el juego abierto. Todo lo demás sigue en inglés.

---

## Corrida abierta: 10-08d — Health panel + body parts + WOUND engine API

**Health panel rediseñado con partes del cuerpo. WOUND usa API real del motor.**
P22-P24 de la corrida anterior siguen vigentes.

**Tres fixes nuevos, más los de corridas anteriores.** Si algo de acá falla, es un bug.

### Antes de arrancar

1. `git pull`.
2. Buscá `ASSERT ---- 30 ok, 0 FAILED ----`. Si dice `FAIL`, pará.
3. Confirmá que estos módulos cargaron:
   ```
   PATHFINDING ready -- preemptive route check before move
   WOUND ready -- healing costs a dressing; every window crossing costs blood (climb watcher every 200 ms, both directions)
   PANIC ready -- your own people no longer read as a horde; spike detector active (logs jumpscares)
   ```

---

### P22 — WOUND: solo daña si el NPC realmente cruzó

**El fix:** cuando el NPC trepa por una ventana con vidrios rotos, el daño SOLO se aplica
si realmente llegó al otro lado. Si la trepada se cancela (hay un zombie, un jugador o un
mueble bloqueando la salida), el NPC se queda en el mismo tile y NO recibe daño.

1. Buscá una ventana con vidrios rotos.
2. Poné un zombie o a vos mismo del otro lado para bloquear la salida.
3. Hacé que el NPC intente cruzar.
4. **Esperado:** el NPC intenta trepar, no puede, y **no recibe daño**. En el log NO debería
   aparecer `WOUND ... cut on broken glass`.
5. Ahora despejá el otro lado y hacé que cruce. **Esperado:** recibe daño normalmente.
   En el log: `WOUND ... cut on broken glass at X,Y | window-climb` o `sweep`.

### P23 — Pathfinding: elige trepar rejas en vez de rodear

**El fix:** `ChooseRoute` ahora evalúa la línea directa entre el NPC y su destino ANTES
de caminar. Si hay una reja (`hop`) o muro alto (`tall`) en el camino, rutea al NPC hacia
la reja para treparla en vez de dejar que el motor la rodee.

1. Buscá un área con rejas o muros entre vos y un compañero.
2. Alejate al otro lado de la reja.
3. **Esperado:** en el log deberías ver:
   ```
   ROUTE <nombre> | blocked by hop at X,Y -- routing to fence crossing | stand X,Y,Z
   ```
   El NPC debería caminar hacia la reja e intentar treparla.
4. Si el NPC sigue rodeando, buscá en el log si siquiera apareció `ROUTE`. Si no aparece,
   `WhatBlocks` no detectó la reja como obstáculo — puede ser que el motor haya encontrado
   un camino que no cruza la reja en absoluto. Si aparece `ROUTE` pero el NPC no trepó,
   el problema está en `GetAccessSquare` o en el bump handler.

### P24 — Tipos de ventana: abre las corredizas, rompe las fijas

**El fix:** cuando el NPC se traba en una ventana, primero intenta abrirla (`OpenWindow`).
Si después de 8 sweeps (~48s) sigue trabado en la misma ventana, es porque no se puede
abrir — entonces la rompe (`SmashWindow`).

1. Buscá una ventana corrediza (de las que se abren).
2. Hacé que el NPC se trabe en ella.
3. **Esperado:** en el log: `blocked by window -- queued OpenWindow`. El NPC la abre y cruza.
4. Buscá una ventana fija (de las que no se abren, como las de baño).
5. Hacé que el NPC se trabe en ella.
6. **Esperado:** primero `queued OpenWindow`, luego (8 sweeps después) `open failed -- queued SmashWindow`. El NPC la rompe y cruza.

---

### P19 — WOUND: vidrios al cruzar (verificado, retestar opcional)

Ya verificado en corridas anteriores. El climb watcher a 200ms detecta cuando el NPC
entra en `ClimbThroughWindowState` y aplica daño al salir. Buscá en el log:
```
WOUND <nombre> cut on broken glass at X,Y | window-climb
```

### P20 — PANIC: jumpscare (verificado, retestar opcional)

Detector confirmado: 3 spikes por sesión, stat max ~30. Buscá:
```
PANIC spike #1 detected | stat=X despite suppression active
```

### P14–P18 — follow, resistencia, rango (verificados)

| Prueba | Veredicto |
|---|---|
| P14 — follow al trotar | ✅ |
| P15 — no se queda pegado | ✅ |
| P16 — te sigue lejos | ✅ |
| P17 — resistencia | ✅ |
| P18 — telemetría | ✅ |

---

### P25 — Panel de salud con partes del cuerpo

**El panel nuevo.** Abrí la rueda sobre un NPC → Health. Deberías ver:
- **Izquierda**: 17 partes del cuerpo con puntos de colores (gris=sano, color=herida)
- **Derecha**: detalles de la parte seleccionada
- **Botón**: venda la parte seleccionada

1. Click en una parte → panel derecho muestra tipo de herida
2. Si tiene bleeding/glass/burn/fracture/infection → aparece en la lista
3. "Zombie virus: X%" muestra la infección
4. Vendaje gasta una venda y aplica vendaje visual

---

## Qué NO hace falta que reportes

- el loot no entra a la mochila;
- juntan lapiceras y cucharas;
- el compañero se congela frente a una ventana estando adentro;
- el miedo cuenta zombis a través de paredes;
- un NPC cerca te levanta del sofá (verificado: no alcanzable desde Lua).
