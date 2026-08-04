# Qué probar ahora

Una sola página. Se reescribe cada vez que una etapa abre o cierra. Si esta página y
cualquier otra se contradicen, ésta es la que está vieja — arreglala.

> **Nota de idioma.** Este archivo va en español porque es el que vos usás mientras jugás.
> Todo el resto — código, comentarios, planes, commits — sigue en inglés.

Hoja de ruta completa: [`docs/plans/README.md`](plans/README.md).

---

## Lo que salió de la corrida anterior

Revisé `logs/console.txt` yo, como pediste. Tres cosas.

**Los puntos de control sí estaban en el código.** Lo verifiqué porque preguntaste: las
líneas `PANEL ready`, `GUARD ready` y `MEMTEST ready` existen (`ScenesRelationsPanel.lua:194`,
`ScenesRelationsGuard.lua:186`, `ScenesRelationsMemoryTest.lua:160`). Lo que pasa es otra
cosa.

**El log es de la build anterior.** Tiene marca de tiempo 19:45 y el commit con panel,
escudo y test de memoria es de las 20:02. Lo que corriste fue `accb957` — la rueda sola.
`git log --diff-filter=A` dice que esos tres archivos nacieron a las 20:02; el log se
escribió 17 minutos antes de que existieran. Por eso no hay ni una línea `PANEL`, `GUARD`
ni `MEMTEST`, y por eso los puntos 1 y 6 no los puedo dar por validados todavía. La prueba está en el propio log: hay
seis `-25 (attacked)` seguidos, que es exactamente lo que el escudo tendría que haber
impedido.

**Una pregunta quedó cerrada y otra tuve que corregirla.**

`HaloTextHelper` **no** funciona sobre un NPC:

```
java.lang.RuntimeException: No implementation found for function:
addText(class zombie.characters.IsoZombie ..., "SCENES probe")
```

Los mensajes que viste sobre la cabeza salían sobre **la tuya**, que es lo que el mod hace
y va a seguir haciendo. Saqué esa sonda: tiraba siete excepciones por sesión para
reaprender algo ya sabido.

**Sobre `getStats()` me equivoqué dos veces, y la segunda la encontraste vos.**

Dije que sus getters fallaban y que por eso había que simular las emociones. Falso. La
sonda llamaba a `stats:getPanic()`, `stats:getThirst()` y cuatro más — **métodos que no
existen en Build 42 ni siquiera para el jugador.** El error no era del motor, era mío.

La API real es un solo accesor genérico sobre un enum:

```lua
character:getStats():get(CharacterStat.THIRST)
```

54 llamadas en vanilla. Y `CharacterStat` tiene **24 valores**, muchos más de los que yo
pedía: `PANIC`, `STRESS`, `ANGER`, `MORALE`, `SANITY`, `PAIN`, `UNHAPPINESS`, `BOREDOM`,
`FATIGUE`, `ENDURANCE`, `HUNGER`, `THIRST`, `TEMPERATURE` y más.

Y no es exclusivo del jugador: `ISAnimalContextMenu.lua:30` hace
`animal:getStats():get(CharacterStat.HUNGER)` sobre un **animal**. Así que el accesor vive
en la clase base y sí está enlazado para personajes que no son el jugador — lo contrario
del caso de `HaloTextHelper`.

**Sobre tu pregunta de Java: no hace falta, y tampoco se puede.** Un mod de PZ es Lua más
datos; no hay ninguna vía en `mod.info` ni en la estructura de carpetas para cargar clases
Java. La única forma sería modificar el JAR del juego, que no se puede publicar en el
Workshop y se rompe en cada parche. Pero la pregunta quedó sin objeto: la palanca ya
existía, yo la estaba llamando mal.

Reescribí la sonda. Ahora imprime cinco estadísticas del NPC más cercano **una vez por
barrido**, así una corrida da una serie en el tiempo en vez de una sola lectura. Diez
barridos de ceros idénticos es una respuesta; que se muevan es la contraria.

---

## Lo que cambió ahora

**Se fueron las teclas K, G y M.** Tenías razón. Verifiqué `shared/keyBinding.lua`: vanilla
reserva **todas** las letras del abecedario menos la K. G y M chocaban de frente.

| Cómo se usa ahora | Qué |
|---|---|
| **V** (mantener) | La rueda. Es la única que conserva tecla — se usa todo el tiempo y lo vale. |
| **Botón en la barra izquierda** | Protección de amigos. Verde prendida, rojo apagada. |
| **Botón en la barra izquierda** | Panel de relaciones. |
| **Consola** | `ScenesRelations.MemTest()` — el test de memoria. |

Los dos botones se agregan **debajo del corazón**, envolviendo `ISEquippedItem` sin
reemplazarlo, así que cualquier otro mod que toque esa columna sigue funcionando.

**El escudo ahora impide el daño, no lo perdona.** Tenías razón en que mi versión erraba el
punto: el miedo no es perder confianza, es matar a alguien sin querer. Ahora vuelve
invulnerables a los aliados cercanos **durante los pocos frames que dura tu propio golpe**
y los suelta al terminar. Un zombi mordiendo a ese mismo sobreviviente no se ve afectado.

Con una salvedad honesta: `setInvincible` está verificado en vanilla pero **siempre sobre un
jugador, nunca sobre un zombi** — que es exactamente el error que acabo de cometer con
`getStats`. Así que va con `pcall`, con la restauración de vida como red, y tres caminos
distintos que quitan la invulnerabilidad para que ningún fallo deje un NPC inmortal.

**La rueda ahora es texto, sin íconos**, como pediste.

**El panel no lo toqué.** Espero tu referencia de diseño.

---

## Antes de empezar

```bash
tools/sync-mods.sh
```

Esta vez importa más que nunca: la corrida anterior midió una build vieja.

Revisá también en **Opciones → Controles** que ya no aparezcan `Relationships`,
`Protect survivors` ni `Memory test`. Si siguen ahí, no sincronizaste.

---

## Las pruebas, en orden

### 1. Todo cargó

**Hacé:** entrá y buscá en `console.txt`.

**Pasa si** están estas seis:

```
SREL| STORE ready
SREL| WHEEL ready
SREL| PANEL ready
SREL| GUARD ready
SREL| MEMTEST ready
SREL| SIDEBAR ready
```

Si falta alguna, decime cuál y paro ahí — el resto de las pruebas no significarían nada.

**Y buscá también estas dos**, que son la sonda de emociones arreglada:

```
SREL| PROBE stat | PANIC ok=true value=...
SREL| PROBE tick | <nombre> | panic=... stress=... thirst=...
```

La línea `PROBE tick` sale una vez por barrido. **Lo que importa no es el valor, es si
cambia entre barridos.** Si se queda clavado en los mismos números toda la sesión, el motor
no los mueve para un NPC y hay que simularlos. Si se mueven solos, la mitad de la etapa 06
desaparece.

---

### 2. Los dos botones nuevos

**Hacé:** mirá la columna izquierda, debajo del corazón.

**Pasa si:**
- Hay dos íconos nuevos: una señal de pare y un ícono de conversación.
- Pasando el mouse sale el texto de cada uno.
- La señal de pare está **verde** (protección activa).

**Si no aparecen** pero sí sale `SIDEBAR ready` en el log, es que el cálculo de posición los
puso fuera de la vista. Decímelo y es una línea.

---

### 3. La rueda con texto

**Hacé:** mantené **V** cerca de alguien.

**Pasa si** cada gajo muestra su nombre escrito — `Talk`, `Follow me` — sin íconos y sin
tener que pasar el mouse.

**Lo que puede fallar:** que los textos estén corridos un gajo. El lado Java no dice dónde
empieza el primer gajo, así que la posición la calculo. Si pasa, son dos constantes.

---

### 4. El escudo — la prueba que más me interesa

**Hacé, en este orden:**

1. Con un aliado al lado, **pegale a propósito varias veces**.
2. Mirá su vida y mirá el panel de relaciones.

**Pasa si:**
- **No recibe daño.** Esto es lo nuevo y lo importante.
- No baja la confianza. En el log: `GUARD absorbed a hit on …`.
- Hacé clic en la señal de pare: se pone **roja**, sale texto rojo, y ahora sí le podés
  pegar y hacerle daño.
- Volvé a hacer clic y queda protegido otra vez.

**Buscá en el log esta línea concreta:**

```
GUARD setInvincible is not available on IsoZombie
```

Si aparece, la invulnerabilidad no funciona sobre NPC y tenemos que ir por otro lado.
Es la línea más importante de toda esta corrida.

---

### 5. **El test de memoria — por consola**

Abrí la consola de debug y escribí, tal cual:

```lua
ScenesRelations.MemTest()
```

1. Antes, conseguí que alguien te tenga confianza y **parate al lado**.
2. Ejecutalo. El log dice `MEMTEST 1/2 LEAVING | id=… trust=…`. Aparecés a 700 tiles.
3. **Esperá** hasta que las líneas `PROBE sweep` dejen de nombrar a esa persona.
4. Ejecutalo **otra vez**. Volvés al mismo lugar.

El log da el veredicto en palabras:

| Línea | Qué significa |
|---|---|
| `MEMTEST VERDICT PASS` | El recuerdo sobrevivió. **La premisa se sostiene.** |
| `MEMTEST VERDICT PARTIAL` | Sobrevivió pero el número cambió. |
| `MEMTEST VERDICT FAIL` | Se perdió, o volvió con otro id. |

La línea siguiente dice si hay un cuerpo con ese id cargado. Si dice `false` **no es un
fallo** — sólo caminó a otro lado. Son dos preguntas distintas a propósito.

Repetilo dos o tres veces.

---

### 6. El panel sigue abriendo

**Hacé:** clic en el ícono de conversación.

**Pasa si** abre igual que antes. **El diseño no lo toqué** — mandame la referencia y lo
rehacemos.

---

## Qué mandarme

`console.txt` y una línea por prueba.

De la 4, la respuesta a *"¿le bajó la vida?"* y si apareció la línea `setInvincible is not
available`. De la 5, las dos líneas `MEMTEST` completas.

---

## En qué estamos

| Etapa | Estado |
|---|---|
| [00 — Mundo de pruebas](plans/00-test-world.md) | construida, confirmada a medias |
| [01 — Memoria durable](plans/01-durable-memory.md) | construida, **sin confirmar** |
| [02 — Rueda de interacción](plans/02-interaction-wheel.md) | rueda aprobada; panel a rediseñar; escudo y barra lateral sin probar |

Sigue: [03 — Vida propia](plans/03-idle-life.md) — que recojan cosas, se las pongan y
looteen donde viven.
