# Análisis independiente de la sesión 11-08

**Segunda lectura del mismo `console.txt` (13.733 líneas), hecha sin leer
[`ANALYSIS-1108.md`](ANALYSIS-1108.md) hasta el final.** La comparación está en la última
sección, y hay tres puntos donde los dos documentos se contradicen con evidencia verificable.

Todo lo que sigue sale de `grep` sobre el log y de leer el código, no de recordar.

---

## 0. El hallazgo que cambia el resto: `getBodyDamage()` devuelve `nil`

**`zombie:getBodyDamage()` es llamable en un `IsoZombie` y devuelve `nil`.** No lanza. No
existe el sistema de partes del cuerpo para un NPC.

Esto importa porque una sesión entera de trabajo se construyó encima de lo contrario.

### La trampa, exacta

La sonda en juego imprimió:

```
PROBE needs | getBodyDamage ok=true value=-
```

Y `ok=true` **se leyó como confirmación**. No lo es. La línea se formatea así
(`ScenesRelationsRun.lua:158-159`):

```lua
SR.Log("PROBE needs | " .. name .. " ok=" .. tostring(ok)
    .. " value=" .. tostring(ok and result or "-"))
```

`ok and result or "-"` con `result == nil` da `"-"`. Así que **`value=-` significa que
devolvió nil**. `ok=true` solo dice que no lanzó una excepción.

Una sonda que reporta éxito para un método que devuelve nada es peor que no tener sonda,
porque produce una cita que el siguiente lector cree.

### Las citas que se dieron como prueba, revisadas una por una

| Cita | Qué hay realmente ahí |
|---|---|
| `ZASmack.lua:358` — *"Bandits ya lo usa en NPCs"* | Está dentro de `Bite(attacker, victim)`, y su **único** llamador es `Bite(bandit, player)` en `ZASmack.lua:608`. `victim` es **el jugador** |
| `ZABandage.lua:50` | Esa línea es `zombie:addVisualBandage(bodyPart.name, true)`. **No llama `getBodyDamage` en absoluto** |

Y barriendo los 22.458 renglones de Bandits: `PlayerDamageModel.lua:5,127,153,176,202`,
`BanditUtils.lua:302`, `BanditPlayer.lua:137`, `BanditServerCommands.lua:277` — **todos sobre
un `IsoPlayer`. Cero sobre un bandido.**

Slayer nunca lo llamó sobre sus propios NPC, y reimplementó el endurance en `brain.endurance`
en lugar de usar el del motor. Eso ya era la señal.

### Consecuencias

- **El panel de salud está muerto.** Renderiza literalmente `Body data unavailable`
  (`caps/npc-health-menu.png`). No es un problema estético: no hay datos.
- **`Wounds` sobrevivió por su fallback.** Cae en `brain.scenesWound` cuando `getBodyDamage`
  no responde, y el log prueba que ese es el camino que corre de verdad.
- Es el mismo modo de fallo que `getSeeNearbyCharacterDistance`, que ya costó una sesión
  entera: un método que existe en la clase compilada y no sirve para lo que se le pide.

---

## 1. Ruteo a rejas: 205 de 205 apuntan a la reja misma

```
blocked by hop at 10717,10085 -- routing to fence crossing | stand 10717,10085,0
                    └───────────── mismo tile ──────────────┘
```

Comprobado sobre las 205 líneas de reja: **el destino es idéntico al obstáculo en el 100%**.
Cero excepciones. El camino de puertas y ventanas hace lo contrario, y bien:

```
blocked by window at 10714,10082 -- routing to the door at ... | stand 10707,10087,0
```

Baldosa distinta — una adyacente real, de `AdjacentFreeTileFinder.FindWindowOrDoor`.

### Pero es deliberado, y hay que decirlo antes de llamarlo bug

`ScenesRelationsPathfinding.lua:121-141` explica el razonamiento: caminar **a** la reja para
que la colisión dispare el bump handler de Bandits (`BanditUpdate.lua:571-577`). La versión
anterior usaba una baldosa de acceso y oscilaba — también documentado, con la frase del
usuario: *"se devolvía para caminar, luego volvía para intentar saltar"*.

**La premisa es razonable. El resultado la contradice:**

| | |
|---|---|
| ROUTE a rejas | **205** |
| `changeState(ClimbOverFence)` | **4** |

Ratio **51:1**. Y los tiles son consecutivos —`10717,10084`, `10085`, `10086`— que es la firma
de un NPC **caminando a lo largo de la reja**, no trabado en una baldosa.

### La hipótesis, y que es una hipótesis

El pathfinder del motor no entra a una baldosa con reja: la rodea. Cada paso del rodeo vuelve a
disparar la detección, y por eso hay 205 líneas y 4 colisiones.

**Esto es inferencia, no medición.** Falta el instrumento que lo decide: registrar si el NPC
**llega** a la baldosa. Es una línea de log y decide el diseño entero; hasta tenerla, cualquier
arreglo es adivinanza. Ver §5.

---

## 2. El climb sí se ejecuta — cuatro veces, y no alcanza

```
f:80371  Julian Brown   @10649.09,10079.5
f:229322 Benjamin Evans @10717,10084
f:233174 Benjamin Evans @10707,10087
f:242769 Benjamin Evans @10717,10085
```

Benjamin trepó en `f:229322` y **seguía ruteando esa misma línea de reja en `f:233195`**, y
volvió a trepar en `f:242769`.

Eso reencuadra el problema. No es *"nunca se intentó"*. Es **"se intentó cuatro veces y no se
sostuvo"** — o el climb no lo cruza, o cruza y el follow lo trae de vuelta al instante. Las dos
tienen arreglos distintos y ninguna se parece a "probar el climb".

El watchdog disparó 9 veces en `hop` y produjo 3 de esos 4 climbs. Funciona; casi nunca le toca
el turno, porque `ChooseRoute` intercepta 13:1 (221 ROUTE contra 17 stalls totales).

---

## 3. WOUND funciona completo, punta a punta

Nueve cortes en dos NPC. **Cinco tagueados `window-climb`** — el watcher de 200 ms, en ambas
direcciones, que es exactamente lo pedido: *"debe hacerle daño cada que entra o salga"*.

```
WOUND Wyatt Watson cut on broken glass | 1.80 -> 1.55 | window-climb
WOUND Wyatt Watson still bleeding | 1.47 -> 1.45 | sweep 5 of 100
WOUND Wyatt Watson dressed with improvised | 1.45 -> 1.45 / 1.80
WOUND Wyatt Watson stopped bleeding -- a dressing went on
```

El ciclo entero está probado en el log: corte → sangra 0.02 por barrido → el NPC decide
vendarse → **el sangrado solo se corta con el vendaje**. `stopped bleeding` disparó cuatro
veces, y `sweep 5 of 100` dice que el tope de seguridad ni se acerca.

El latch de `bleeding` —el patrón que ya costó cuatro defectos en este proyecto— **es
alcanzable, y está demostrado en juego**, no argumentado.

---

## 4. Lo que nadie nombró: Julian casi se mata cruzando la misma ventana

```
cut at 10622,10048 | 1.39 -> 1.14 | sweep
cut at 10622,10048 | 1.14 -> 0.89 | window-climb
cut at 10622,10048 | 0.89 -> 0.64 | window-climb
cut at 10622,10048 | 0.60 -> 0.35 | window-climb
cut at 10622,10048 | 0.41 -> 0.16 | window-climb
```

Cinco cruces de **la misma ventana**, de 1.39 a 0.16 de vida.

El daño por vidrio no está mal calibrado: está **amplificado por la oscilación del §1**. Es la
misma causa con otra cara, y arreglar el ruteo lo arregla solo. Bajar el daño ahora sería tapar
el síntoma y perder la señal.

---

## 5. La escalera está sana; el reloj de huida sigue sin probarse

```
rung:  obey 62 | fight 21 | survive 7 | idle 2
dis=true 19/92 (21%)   lock=true 22/92 (24%)
flee=true  2/92 (2%)
```

Las decisiones se ven razonables y los candados de la tarea de follow se aplican.

Pero **`flee=true` en 2 de 92 muestras**: no hubo casi ninguna corrida de cinco segundos
seguidos esta sesión. La feature de huida por tiempo **no está validada**, solo cargada. Eso hay
que probarlo a propósito, no esperar a que salga.

---

## Comparación con `ANALYSIS-1108.md`

### Donde coincidimos

- El bucle de ruteo de rejas es lo primero y es urgente.
- El `obstacleAttempts` por tile no protege mientras el jugador se mueve.
- El spike de pánico es comportamiento esperado.
- El panel de salud no se parece al del jugador y hay que rehacerlo.

### Tres afirmaciones que el log contradice

| `ANALYSIS-1108.md` dice | El log dice |
|---|---|
| *"cero líneas de `changeState(ClimbOverFence)`"* | **Cuatro**, con frame y NPC |
| *"No hubo cortes de vidrio en esta sesión"* | **Nueve cortes**, cinco por `window-climb`, más el ciclo de vendaje completo |
| *"El watchdog NUNCA disparó para rejas"* | Disparó **9 veces** en `hop` y produjo 3 de los 4 climbs |

Y una cuarta, la más cara: *"se confirmó que `getBodyDamage()` … SON llamables en `IsoZombie`.
Bandits ya los usa en `ZASmack.lua:358` y `ZABandage.lua:50`"*. Las dos citas son incorrectas
(§0), y el método devuelve `nil`.

### Donde discrepo en el diagnóstico, no solo en los hechos

Su cadena del bucle es: `ChooseRoute → ROUTE Move → el NPC camina al tile → re-evalúa → misma
reja`.

**Se detiene un paso antes de la causa.** El NPC no "camina al tile" — por eso los tiles del log
son consecutivos en lugar de repetidos. Su arreglo propuesto (cooldown por radio más amplio)
haría el bucle más lento, no lo eliminaría.

Y su *"urgente #2 — el climb nunca se ejecuta, probarlo directamente en el watchdog"*: **eso ya
pasa y ya se probó**, cuatro veces. Esa recomendación gasta una sesión en confirmar algo que el
log ya respondió.

---

## Qué haría, en orden

1. **El instrumento antes que el arreglo.** Registrar si el NPC llega a la baldosa de la reja.
   Decide entre "el bump handler es viable" y "hay que volver a baldosa adyacente + acción de
   climb explícita". Una línea de log contra una sesión de adivinanza.
2. **Panel de salud sin `getBodyDamage`.** No hay datos por parte del cuerpo para un NPC. El
   panel tiene que mostrar lo que existe —condición, virus, nuestro propio registro de heridas—
   con la forma del panel del jugador, y decir una vez que el motor no expone partes para NPC,
   en lugar de listar diecisiete partes con valores inventados.
3. **Probar la huida a propósito.** Correr cinco segundos seguidos y buscar `flee=true`.
4. **No tocar el daño por vidrio todavía.** Es una consecuencia del §1.
