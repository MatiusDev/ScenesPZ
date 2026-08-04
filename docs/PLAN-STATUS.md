# Qué probar ahora

Una sola página. Se reescribe cada vez que una etapa abre o cierra. Si esta página y
cualquier otra se contradicen, ésta es la que está vieja — arreglala.

> **Nota de idioma.** Este archivo va en español porque es el que vos usás mientras jugás.
> Todo el resto — código, comentarios, planes, commits — sigue en inglés.

Hoja de ruta completa: [`docs/plans/README.md`](plans/README.md).

---

## Antes de empezar

```bash
tools/sync-mods.sh
```

Después abrí **Opciones → Controles (Key Bindings)** y confirmá las cuatro teclas nuevas.
Todas se pueden reasignar ahí; si otro mod ya usa alguna, cambiala y listo.

| Tecla | Qué hace |
|---|---|
| **V** (mantener) | Rueda de interacción sobre el sobreviviente más cercano |
| **K** | Panel de relaciones — las barras |
| **G** | Prende y apaga la protección contra golpear amigos |
| **M** | Test de memoria (dos toques) |

No hace falta partida nueva, salvo que quieras el compañero inicial.

---

## Las pruebas, en orden

### 1. Todo cargó

**Hacé:** entrá a la partida y abrí `console.txt`.

**Pasa si** aparecen estas cinco líneas al arrancar:

```
SREL| WHEEL ready
SREL| PANEL ready
SREL| GUARD ready
SREL| MEMTEST ready
SREL| STORE ready | 32 shards | N records recovered from this save
```

**Si falta alguna,** ese archivo no cargó y las pruebas que dependen de él no tienen
sentido. Decime cuál falta antes de seguir.

---

### 2. La rueda ahora se lee

**Hacé:** parate cerca de un sobreviviente y **mantené V**.

**Pasa si:**
- El nombre de cada acción se ve **escrito dentro de su gajo**, sin tener que pasar el
  mouse por encima. Eso era lo que estaba mal.
- Abajo de la rueda está sólo el **nombre** de la persona.
- El puntaje de confianza **ya no aparece acá**. Se mudó al panel.
- Las acciones bloqueadas se ven grises, con el motivo debajo — por ejemplo
  `Follow me` / `(needs 25 trust)`.

**Lo que puede fallar y no es grave:** que los textos estén corridos un gajo respecto de
los dibujos. El motor dibuja la rueda del lado Java y no nos dice dónde empieza el primer
gajo, así que lo calculé. **Si pasa, decímelo y son dos constantes** — están marcadas en el
código como `FIRST_SLICE_ANGLE` y `CLOCKWISE`.

---

### 3. Hablar sube la confianza

**Hacé:** abrí la rueda sobre un desconocido y elegí **Talk**. Repetí varias veces.

**Pasa si:**
- Sube `+4` por conversación y sale texto verde sobre **tu** cabeza.
- Si lo intentás enseguida otra vez dice `Talk` / `(nothing more to say yet)`. El descanso
  es media hora de juego, más o menos 3 minutos reales.
- Después de suficientes charlas, `Follow me` deja de estar gris.

Es a propósito más lento que pelear al lado de alguien. Si te resulta *tan* lento que no
vale la pena, decímelo y muevo el número.

---

### 4. El panel de relaciones

**Hacé:** presioná **K**.

**Pasa si:**
- Se abre una ventana con una fila por cada persona que conociste.
- Cada fila tiene nombre, una barra, y abajo el nivel y el número.
- La barra va de -100 a 100 con una **línea blanca en el cero**: llena hacia la derecha en
  verde si confían, hacia la izquierda en rojo si desconfían. Que alguien te desconfíe y
  que alguien no te conozca tienen que verse distinto.
- Los que están cerca en este momento dicen `here` a la derecha.
- Se puede arrastrar y redimensionar. Se cierra con K de nuevo.

**Ojo con esto:** los registros creados *antes* de este build no guardaron el nombre, así
que van a aparecer como `#4823`. No es un error — se arregla solo la próxima vez que
interactúes con esa persona.

---

### 5. La protección contra golpes accidentales

**Hacé:** con un sobreviviente amigo al lado, **pegale a propósito**.

**Pasa si:**
- **No** baja la confianza. En el log sale `SREL| GUARD absorbed a hit on … -- no trust lost`.
- Presionás **G**, sale texto rojo *"Survivors UNPROTECTED"*, le pegás de nuevo, y **ahora
  sí** baja `-25`.
- Presionás **G** otra vez y vuelve a estar protegido. Arranca siempre protegido.

**Lo que quiero que mires bien:** ¿el golpe le quita vida igual, aunque no cueste confianza?

No hay ningún evento en 42.20 que permita **cancelar** un golpe antes de que pegue —
verifiqué los cinco que existen. Así que esto no impide el golpe, lo deshace. Lo que está
garantizado es que no te cueste la relación. Devolverle la vida depende de que `setHealth`
funcione sobre un NPC, cosa que no está confirmada en ningún lado. Si no funciona, el log
lo va a decir una vez con `GUARD setHealth is not available on IsoZombie`.

---

### 6. **El test de memoria — el que decide todo**

Este es el que no se pudo hacer antes porque había que caminar demasiado. Tenías razón: una
celda de Project Zomboid mide **300 × 300 tiles**, así que diez cuadras no alcanzaban ni de
cerca.

Ahora se teletransporta. No hace trampa: se va lo bastante lejos para que el motor descargue
la celda **de verdad**, igual que caminando, y vuelve.

**Hacé, en este orden:**

1. Conseguí que un sobreviviente te tenga confianza — hablale o peleá a su lado hasta que
   la barra en el panel (K) esté claramente del lado verde.
2. Parate **al lado de esa persona** y presioná **M**.
   - El log dice `MEMTEST 1/2 LEAVING | id=… name=… trust=…`. **Anotá ese id y ese trust.**
   - Aparecés a 700 tiles de distancia.
3. **Esperá.** Mirá el log hasta que las líneas `PROBE sweep` dejen de mencionar a esa
   persona. Eso significa que su celda se descargó. Un minuto real alcanza de sobra.
4. Presioná **M** otra vez. Volvés al lugar exacto.

**El log te da el veredicto en palabras, no tenés que interpretarlo:**

| Línea | Qué significa |
|---|---|
| `MEMTEST VERDICT PASS` | El recuerdo sobrevivió intacto. **La premisa del mod se sostiene.** |
| `MEMTEST VERDICT PARTIAL` | Sobrevivió pero el número cambió. Algo más está escribiendo encima. |
| `MEMTEST VERDICT FAIL` | Se perdió. O el almacén no persiste, o volvió con otro id. |

Después sale una línea más: `MEMTEST body with that id currently loaded: true/false`. Si
dice `false` **no es un fallo** — sólo significa que esa persona caminó a otro lado. Son dos
preguntas distintas y las separo a propósito, porque confundirlas es cómo uno concluye "me
olvidó" cuando en realidad se movió.

**Repetilo dos o tres veces.** Es barato ahora y es la respuesta más importante que falta.

---

### 7. Dos segundos mirando la pantalla

Al principio de la sesión el log escribe dos líneas `PROBE halo`.

**Mirá la pantalla** y decime si las palabras *SCENES probe* aparecieron **sobre la cabeza
del NPC**.

Ahora mismo todos los mensajes salen sobre **tu** cabeza, porque es la única posición
comprobada en vanilla. Si funciona sobre un NPC, se mueve una sola función y todo se lee
muchísimo mejor. **Una palabra alcanza.**

---

## Qué mandarme

`console.txt`, más una línea por prueba: número, pasó o no, qué viste.

De la prueba 6 lo importante son las dos líneas `MEMTEST` completas. De la 7, una palabra.

No borres el log entre pruebas.

---

## En qué estamos

| Etapa | Estado |
|---|---|
| [00 — Mundo de pruebas](plans/00-test-world.md) | construida, confirmada a medias |
| [01 — Memoria durable](plans/01-durable-memory.md) | construida, **el test de descarga nunca se pudo correr** |
| [02 — Rueda de interacción](plans/02-interaction-wheel.md) | rueda probada y aprobada; panel, escudo y test de memoria recién construidos |

Sigue: [03 — Vida propia](plans/03-idle-life.md) — que recojan cosas, se las pongan, y
looteen donde viven.
