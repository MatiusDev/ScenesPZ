# Registro de corridas

**Este archivo solo CRECE. Nunca se reescribe, nunca se corrige hacia atrás.**

Esa forma es deliberada. La auditoría del 09-08 encontró que los documentos a los que los
eventos les *agregan* se mantienen frescos, y los que habría que *reescribir* se pudren, porque
nadie reescribe. Este es de los primeros. Lo que quedó mal escrito acá se corrige con una
entrada nueva que lo dice, no editando la vieja — un veredicto tachado enseña más que uno
borrado.

Qué probar **ahora**: [`docs/TESTING-NOW.md`](TESTING-NOW.md). Este archivo es lo que ya pasó.

---

## 10-08 (segunda corrida) — P12 y P13 cerradas, y la causa del "se queda pegándole a los zombies"

### P13 — las dos sondas de puerta: **PASAN, ambas son llamables**

```
PROBE door | isExterior      ok=true value=true   (y value=false en otra casa)
PROBE door | isExteriorDoor  ok=true value=true   (y value=false)
PROBE blocks | E/W/N/S = door, hop, solid, locked
PROBE blocks | E/W/N/S = locked, solid, solid, solid
```

`ok=true` en las dos, y **con valores distintos según dónde estaba parado** — que es la prueba
que importaba. Un método que devuelve siempre lo mismo no es un método que funciona, es un
método que no mira nada. No fueron el caso de `getSeeNearbyCharacterDistance`.

**Consecuencia:** el orden de entrada que pediste — *puerta primero (con llave o no) → siguiente
puerta **exterior** → ventana más cercana → romper de último* — es implementable **tal como lo
dijiste**, sin reescribirlo en términos geométricos. Y `WhatBlocks` ya distingue los cuatro
tipos en la misma línea.

### P12 — la proporción de obstáculos: **medida, y confirma la corrida anterior**

27 muestras de `blocked by` en las dos capturas:

| Valor | Veces | % |
|---|---|---|
| `solid` | 14 | 52% |
| `clear` | 11 | 41% |
| `locked` | 1 | 4% |
| `hop` | 1 | 4% |
| `door` | **0** | **0%** |

**Cero puertas cerradas sin llave.** Segunda medición independiente que dice lo mismo que la
primera: escribir una acción de puerta arreglaría entre el 0% y el 8% de los atascos. El
trabajo real está en el 41% de `clear` — se trabó con la línea recta despejada, o sea que el
obstáculo **no estaba sobre la línea**, que es exactamente el punto ciego de `WhatBlocks` por
construcción.

Esto no cancela el bloque de puertas; lo despriorizá. La medición pagó dos veces lo que costó.

### El hallazgo de la ronda: por qué deja de seguirte para pelear

`obey -> fight` es **la transición más frecuente de todo el log — 36 veces**, y las muestras
dicen con qué:

```
AUTO Leo Collins | obey -> fight | fear=14/83 z=1@5.2 friends=1 hp=1.00 | queue cleared
AUTO Leo Collins | obey -> fight | fear=13/83 z=1@0.6 friends=1 hp=0.92 | queue cleared
```

**Un solo zombi.** No es una horda ni el miedo — `fear=13/83` es tranquilidad. Son dos causas
sumadas, y ninguna se veía en el log hasta ahora:

1. **`isSprinting()` no es correr.** Todo el mod leía solo ese método. En PZ *esprintar* (shift)
   y *correr* son estados distintos, y `isRunning()` existe y es llamable —
   `pzserver/media/lua/client/Foraging/ISBaseIcon.lua:700`,
   `pzserver/media/lua/client/Tutorial/Steps.lua:1994`. Cuando corrías sin esprintar, el
   compañero no tenía forma de saber que te estabas yendo.

2. **`ManageCombat` de Bandits le quita la cola cada tick.** Llama a `Bandit.ClearTasks` y mete
   su `Smack` en cuanto hay un enemigo a 2.6 tiles afuera / 1.2 adentro
   (`vendor/Bandits/mods/Bandits/42.20/media/lua/client/BanditUpdate.lua:961`). Nuestra tarea de
   seguirte no sobrevivía a eso, así que aunque decidiéramos bien, el motor la borraba.

**El lever que lo resuelve estaba ahí desde siempre y nadie lo había leído:** `Bandit.ClearTasks`
**conserva** las tareas con `task.lock == true` (`Bandit.lua:369-382`), y las tareas de combate
se **agregan al final** con `table.insert` (`BanditUpdate.lua:1911`), nunca al principio. Una
tarea de seguimiento bloqueada sobrevive el vaciado y se queda a la cabeza; el `Smack` queda
detrás. Es exactamente *"no quedarse peleando contra los zombies"*.

### Lo demás que dijo el log

| Observación | Qué significa |
|---|---|
| `Dylan James \| rung=idle ... master=37.8 ... head=Time@nil,nil/-` | un NPC a 38 tiles sentado sin hacer nada. `NPC_RANGE = 40` era el borde: pasando eso el barrido **lo saltea entero** — sin rung, sin seguimiento, sin watchdog. Un compañero que se quedaba atrás quedaba abandonado, y eso es *"me alejé mucho y no fue capaz de regresar"*. |
| `friends=0` en todas las líneas lejanas | la confianza de grupo no llegaba a quien más la necesitaba. |
| `end=` no existía en el censo | las dos hipótesis de cansancio ("se cansa en medio camino") **no se podían ni confirmar ni refutar** con el log que teníamos. Por eso esta ronda agrega `end=`, `run=` y `lock=`. |

### Lo que el log NO pudo decir, y hay que anotarlo

*"Los logs no logran atrapar todos los errores que describo, entonces estás a ciegas."* Cierto,
y es la razón por la que esta ronda es mitad instrumentos y mitad arreglos. Nada en el log
mostraba el momento en que `ManageCombat` se robaba la tarea — se veía el síntoma (`obey ->
fight`), nunca el robo. Ahora hay una línea por episodio que lo dice.

Sigue sin verse: no saltar el muro alto (lo intenta y cae del mismo lado) y quedarse trabado
en el marco de una ventana. Los dos están fotografiados (`caps/npc-window-stuck_2.png`) y
ninguno produce una línea propia. Es trabajo del bloque de entrada/salida.

---

## 10-08 — bloque de puertas abierto, y tres cosas cerradas

### Lo que se cerró

| Prueba | Veredicto |
|---|---|
| **P0** errores de motor en `console.txt` | **PASA.** Cero. Los generaba una aserción nuestra que llamaba a un método inexistente dentro de un `pcall` para probar que seguía sin existir; el `pcall` lo atrapaba y la prueba pasaba, pero el motor imprimía igual su traza Java **en cada arranque**. La aserción fabricaba la alarma que venía a prevenir. Eliminada. |
| **P2** parpadeo del pánico | **PASA.** El patrón de decidir lento / aplicar rápido funcionó. |
| **P3** el pánico no queda apagado | **PASA.** Ni un `fast suppression is OFF` en toda la sesión. |
| **P6** una sola mochila en el cadáver | **PASA.** El duplicado salía de que `UpdateItemsToSpawnAtDeath` arma el cuerpo desde el inventario vivo **y** desde `brain.bag` por separado; el paso de vestir metía una mochila real al inventario y se convertía en la segunda. |
| **P9** dejan de lootear y siguen al jugador | **PASA, y con consecuencia de diseño.** Funciona con `ClearTasks`, que era justo lo que el paso 4 del plan venía a reemplazar. El paso 4 arreglaría un problema que ya no se reporta. |
| **P10** la mochila se ve al instante | **PASA.** |

### El hallazgo de la ronda

`Bandit.ApplyVisuals` — la función que **ya llamábamos** — empieza con:

```lua
local skin = banditVisuals:getSkinTexture()
if not skin or skin:find("^FemaleBody") or skin:find("^MaleBody") then return end
```

`FemaleBody`/`MaleBody` **son las texturas normales**. En cualquier NPC ya vestido y a la vista, la función **se salía en la línea 84** y nunca llegaba al bloque de la mochila. Tres intentos —`setWornItem`, `resetModelNextFrame`, `resetModel`— fueron todos la pregunta equivocada.

El rodeo es de Slayer: The Ark viste NPC vivos delante del jugador poniendo `setSkinTextureName("x")` antes de llamar, porque `"x"` no matchea ninguno de los dos patrones. Su propio `-- sic!` anota que se ve mal y es a propósito.

**La lección:** yo había cerrado esto dos veces como *"verificado: no alcanzable desde Lua"*, con evidencia bien argumentada. Era una conclusión sólida sobre evidencia incompleta — la forma más peligrosa de estar equivocado, porque no se siente como una duda. Se destrabó porque el usuario insistió en no guiarnos por las limitaciones.

### Lo que se descartó, y por qué vale

**El corte de interrupción rápida (paso 3) se escribió, se revisó y NO se commiteó.** La premisa era falsa: `ManageCombat` corre cada tick de Bandits y **vacía la cola por su cuenta** para meter el ataque (`BanditUpdate.lua:1210-1212`). "Está looteando y lo muerden, suelta el cajón" nunca estuvo bloqueado.

Y el interruptor era **dañino**: cancelaba a 4 tiles, pero Bandits solo pelea a `1.2` adentro. Entre 1.2 y 4 —donde se lootea— cancelaba una tarea que nadie iba a reemplazar. **Hasta 60 segundos de parálisis.**

**Invariante que queda:** un rango de interrupción tiene que ser **menor o igual** al rango en que algo lo reemplaza. Cancelar más lejos que el alcance del reemplazo crea una banda muerta.

**El seguimiento (44dde76) se revirtió** por tres defectos: la función era código muerto (la tarea vive 0.33 s contra un throttle de 800 ms), la ruta al refugio se acumulaba, y una interrupción de seguimiento hacía que Loot registrara un rechazo falso que **borra el mueble a los tres**.

### Números que se movieron

| Señal | Antes | Después |
|---|---|---|
| `gives up ... could not get there` | 96 | **34** |
| errores de motor por arranque | 1 | **0** |
| `carrying` sobre capacidad | 139% | dentro del límite |

El 139% salía de que el presupuesto sumaba la capacidad de la mochila a un techo medido contra el **inventario principal**, al que una mochila puesta no aporta nada.

### Herramientas que salieron de esta ronda

- **`tools/audit.py`** — la mitad mecánica de una revisión: latches sin limpieza, vida real de las tareas en segundos, sitios de cirugía de cola, citas a vendor sin carpeta de versión, `pcall` descartados, y `luacheck` con un allowlist de 7.342 globales cosechado de los árboles reales.
- **Un hueco que el lint tenía y nadie sabía:** el `luac` local es **5.5** y el juego corre **Kahlua 5.1**. Aceptaba `goto`. Ahora hay un chequeo bloqueante.
- **Hook de `pre-push`** por `core.hooksPath`, así que viaja con el repo y también protege la PC de juego.


Más nuevo arriba.

---

## 09-08 — bloque A cerrado

**Probado con:** `ac191ca` + la tanda del 08-08 de noche. 19 aserciones, log de 1,4 MB.

| # | Qué era | Veredicto |
|---|---|---|
| A0 | los asserts pasan | ✅ `ASSERT ---- 19 ok, 0 FAILED ----` |
| A1 | se acerca a cada mueble antes de abrirlo | ✅ *"me parece increíble como ha mejorado esto"* |
| A2 | cero `LOOT refused` | ✅ **cero**, en todo el log |
| A3 | levanta la mochila y se la pone | ⚠️ se la pone, pero **no se veía** → arreglado el 09-08, se re-prueba como B2 |
| A4 | la mochila queda en el cadáver una sola vez | ✅ |
| A5 | lo que agarra es útil y aparece al morir | ✅ *"tenían todos los objetos obtenidos en su mochila"* |
| A6 | suelta lo recogido tras un despawn | ✅ `Restore` en el log |
| A7 | un NPC libre levanta ropa del piso | ⏳ sin probar, pasa a la corrida siguiente |

### Lo que aprendimos, que vale más que el veredicto

**La hipótesis del usuario era razonable y estaba equivocada, y el log lo zanjó en tres números.**
La sospecha era que dejaban de lootear por tener el inventario lleno. Lo que había:

| Señal | Cuenta |
|---|---|
| `stops searching -- full` | **0** |
| `stops searching -- nothing left within reach` | 26 |
| muebles efectivamente abiertos | 15 |
| **`gives up on X,Y -- could not get there in 3 tries`** | **111** |

Abandonan ~7 muebles por cada uno que abren, **porque no logran llegar**. Las coordenadas se
agrupan en casillas contiguas: muebles de la misma habitación.

**Y eso resultó ser la misma causa de un síntoma que parecía no tener relación** — que se traban
contra puertas y ventanas. No son dos bugs. Nunca preguntamos si el NPC puede *alcanzar* la
casilla, y no hay paso de abrir puerta. Un mueble en un cuarto cerrado quema los 3 intentos
contra la puerta y se descarta.

**Lección de método:** una queja de jugabilidad ("solo revisa algunos cajones") y una queja de
navegación ("se traban en las puertas") pueden ser el mismo defecto. Contar líneas del log antes
de diseñar la solución evitó construir un "checklist de cajones" que no habría arreglado nada.

### Hallazgos de código

- **`GetAccessSquare` devuelve casillas inalcanzables a propósito.** Slayer escribió el chequeo
  y lo dejó comentado, en las dos copias — `42.20/BanditUtils.lua:1051` y `:1070`:
  `-- if AdjacentFreeTileFinder.privTrySquare(...) and testSquare:canReachTo(gridSquare) ...`
  `canReachTo` es real (`luautils.lua:140`) pero **solo valida adyacencia**
  (`ISEntityUI.lua:560`): responde "¿puedo dar este paso?", no "¿puedo cruzar la casa?".
- **Bandits trae `ZAOpenWindow`, `ZASmashWindow`, `ZAClimbFence` — y ninguna acción de puerta.**
- **The Ark no aporta nada para entradas.** Sus 27 acciones son vida doméstica: `Cook`, `Eat`,
  `SitInChair`, `SleepLong`, `UseRadio`, `CleanFloor`, `PlayPiano`. Sirven para el "idle" de los
  NPC libres, no para navegar.
- **La mochila no daba capacidad. Ninguna.** El presupuesto salía de
  `getInventory():getMaxWeight()`, el contenedor principal; en PZ una mochila es un contenedor
  aparte. Framepack de 35 y escolar de 15 compraban lo mismo: nada. Por eso también quedaban
  objetos fuera de la mochila al morir — todo estaba en el inventario principal.
- **La mochila no se veía porque nunca se equipaba**, no por el modelo: `ApplyVisuals` ya llama
  `resetModel()` (`Bandit.lua:280`). La línea que la pone está comentada en `:249`.
- **El pánico por NPC amigos: Slayer lo resolvió y lo apagó.** `PanicHandler`
  (`BanditPlayer.lua:132`) está completo y muerto en la línea siguiente: `if true then return end`.
- **La pistola del kit nunca pudo dispararse.** Declara `MagazineType = Base.9mmClip`; le
  dábamos la caja de balas y ningún cargador. **Toda observación previa sobre NPC y armas de
  fuego se hizo con un arma que no podía disparar** y hay que rehacerla.

---

## 08-08 (noche) — el primitivo compartido, y un bug cazado en revisión

**No llegó a probarse en juego como corrida propia**; entró junto con la del 09-08.

### Qué entró

- **Un solo primitivo caminar-luego-actuar**: `SR.Move.GoAndDo` (`ScenesRelationsMove.lua`),
  copiado de `BWOAPrograms.GoAndDo` de The Ark. Esa decisión estaba escrita a mano en cuatro
  lugares y el mismo bug había aparecido en dos.
- **Bandits y Week One actualizados** (08-06 y 08-07).
- 3 aserciones nuevas (19 en total en ese momento).

### La lección, y es la más cara de la semana

**Un subagente escribió el primitivo bien y mató un comportamiento entero en silencio.**
`SR.Move.GoAndDo` devuelve el movimiento **o** la acción, nunca las dos — correcto. Se cableó en
tres lugares. Dos vivían dentro de programas de Bandits, que **vuelven a correr solos cada vez
que la cola de tareas se vacía**, así que devolver una pata por vez funcionaba. El tercero,
`ScenesRelationsIdle.goGet`, corría desde un barrido `EveryOneMinute` detrás de un candado
`mood.wanting` cuyo único trabajo era **impedir la segunda llamada**.

Encolaba la caminata, la cola se vaciaba, el `PickUp` nunca se encolaba, y el barrido concluía
que el NPC se había rendido. Cada vez. **`lint.sh` pasó.**

Quedó escrito como **R13b** en `docs/CODE-REVIEW-RULES.md`: *cambiar una función obliga a leer
cada caller y nombrar qué lo re-invoca.* No la línea de llamada — el loop o evento donde vive.

Segunda lección, del harness: **el subagente murió por límite de gasto antes de reportar, y el
código quedó en disco sin que nadie lo leyera.** De ahí salió la regla de que ningún output de
un writer llega a un commit sin `pz-review`, y de que un writer que no reportó no produjo trabajo
verificado.

---

## 05-08 (noche) — bloque A, segunda vuelta

**Probado con:** el fix de `isBag`. 10 aserciones.

| # | Reportaste | Veredicto |
|---|---|---|
| A0 | pasan | ✅ `ASSERT ---- 10 ok, 0 FAILED ----` |
| A1/A2 | siguen loteando desde el punto | ❌ confirmado, y era un patrón, no un bug suelto |
| — | "cogen un montón de cosas que no sirven" | ❌ confirmado con aritmética: John James pasó de `carrying 0.2` a `6.3` en **3 ítems**, contra un presupuesto de 5.6 |
| A3/A4 | recoge la mochila, no se la pone, no queda en el cadáver | ❌ confirmado, y son **dos** fallos distintos |
| A5 | "sí aparecían ítems" | ⚠️ 3 × `got N item(s) back after a respawn` — `Restore` funciona, pero lo del cadáver podía ser botín aleatorio de Bandits |
| A6 | — | ✅ 6 × `stops searching -- full` |

### La causa, que fue la lección estructural del proyecto

No era la casilla adyacente. Era **el orden de la cola**:

```lua
if dist > 0.9 then tasks[#] = GetMoveTask(...) end
tasks[#] = { action = "ScenesLoot", x = spot.x, y = spot.y }
```

Una tarea de movimiento en Bandits garantiza que **terminó**, nunca que **llegó**. Camino
bloqueado, puerta, empujón, o la escalera de amenaza vaciando la cola: todo eso la termina antes
de tiempo, y la tarea siguiente corría igual, leía sus coordenadas y vaciaba un ropero al otro
lado del cuarto.

**Slayer nunca tuvo este bug porque nunca escribe una cola que no puede verificar.** Un programa
solo corre con la cola vacía, así que dividir sale gratis: camina → cola vacía → el programa
corre otra vez → ahora sí está al lado → actúa. La distancia se mide **al llegar**, no se
predice.

Quedó como **R13** en `docs/CODE-REVIEW-RULES.md`.

### Y el diagnóstico de calidad que salió de acá

| | The Ark | Nosotros, antes |
|---|---|---|
| Acciones registradas | 27 | 8 |
| Decisiones "andá y hacé" | **35** | 4 |
| Implementaciones de esa decisión | **1** (41 líneas) | **4**, cada una a mano |

El síntoma que lo delató: **el mismo bug arreglado dos veces en un solo commit.** El costo
marginal de un comportamiento nuevo para Slayer es ~20 líneas; el nuestro era ~200 con un bug
nuevo adentro. Él construye la capa aburrida primero — `GoAndDo`, `PermaInv`, `GetItemClass`,
`GetAccessSquare` — y las features salen triviales.

---

## 04-08 — bloque A, primera vuelta: lo que recogen es de verdad

**Un método equivocado rompió cuatro síntomas a la vez.**

**Una mochila no tiene `BodyLocation`.** Se usaba `item:getBodyLocation() == "Back"` para
reconocer un bolso. Ese campo es de **ropa**. Un bolso es un `InventoryContainer` y se declara
con `CanBeEquipped = base:back` — no tiene `BodyLocation` en absoluto.

Consecuencias: no recogía la mochila del suelo; la meta "buscar mochila" nunca se cumplía — las
28 búsquedas del log dicen `for bag` y ninguna la encontró; la que salió de un cajón salió como
relleno; y nunca se la equipó. **1.422 líneas `SREL` y cero `found what it wanted`.**

**Y lo que recogían no era real.** Bandits guarda las pertenencias en el `brain`, no en
`zombie:getInventory()`. Nunca llamábamos `Bandit.UpdateItemsToSpawnAtDeath`, así que la lista de
muerte seguía congelada en la del spawn. El log lo mostraba sin matar a nadie: Daniel Green subió
de `carrying 1.5` a `5.6` y **reapareció con 1.5**, conservando el nombre. **El cerebro sobrevive
al despawn; el inventario no.**

### La lección que quedó como R2

`getBodyLocation()` es real, tiene 107 callsites en `pzserver/media/lua/`, y devuelve exactamente
lo que uno espera — **sobre ropa**. R1 pedía un callsite real y había uno: en una remera. De ahí
salió el arnés de aserciones que corre dentro del juego, porque `luac` compila una respuesta
equivocada igual de contento que una correcta, y el smoke test del servidor **nunca ejecuta
`media/lua/client/`**, que es casi todo este mod.

---

## Confirmado antes del bloque A — no repetir

| Qué | Evidencia |
|---|---|
| Memoria durable entre descargas de celda | corrida 03-08 |
| La rueda de interacción | *"ya se comporta mejor"* |
| Corte con vidrios rotos | `cut on broken glass \| 1.80 -> 1.55` |
| Arma silenciosa adentro de una casa | 5 × `goes quiet indoors` — **nunca había disparado** |
| Sentarse dejó de ser constante | *"si se sientan, y lo hacen menos seguido que antes"* |
| Cast out / expulsar | *"esto funciona correctamente"* |

---

## Corrida 10-08: diagnóstico de trabas (P12-P13) — cerrada sin veredicto, datos recolectados

### Contexto

La corrida 10-08 fue puramente diagnóstica: P12 medía qué objetos traban a los NPC, P13
probaba si `isExterior` / `isExteriorDoor` son llamables desde Lua. La respuesta de P12
iba a decidir si el trabajo siguiente era una acción de puerta o algo más profundo. La de
P13 iba a decidir si "la siguiente puerta exterior" puede formularse con la API del motor
o hay que rehacerla en términos geométricos.

### Resultado

El usuario no llegó a reportar los datos de P12/P13 antes de que otras quejas (follow vs
fight, resistencia, rango de abandono) movieran la prioridad. Las pruebas quedan como
datos pendientes, no como fallos. Se retomarán cuando el bloque B (entrada a edificios)
esté abierto — la respuesta de P12 es literalmente lo que decide cómo empieza ese diseño.

### Lo que sí se recolectó

- **P12 (proporción de trabas):** sin datos del usuario. Los conteos internos de la sesión
  anterior (08-08) daban 12 `solid`, 11 `clear`, 1 `locked`, 1 `hop`. Pero esos conteos
  son de antes del cambio de `STUCK_SWEEPS` y del `WhatBlocks` que distingue `door` de
  `solid`, así que no son comparables.
- **P13 (sonda de puertas):** sin respuesta. Si `isExterior` / `isExteriorDoor` tiran
  `ok=false`, la regla de búsqueda de puertas exteriores se rediseña con geometría pura
  (el NPC solo puede estar adentro de UN edificio, así que "exterior" = "la puerta que
  da a una casilla que no está en ese edificio").

---

## Corrida abierta 10-08b: follow vs fight, resistencia, rango

**Inicio:** 2026-08-10. Tres quejas del usuario atacadas con cambios de comportamiento,
no de diagnóstico:

1. **"Me alejé mucho y no fue capaz de regresar a mi lado"** → `LOST_RANGE = 150` para
   compañeros propios, camino barato sin escaneo de caché.
2. **"Se queda pegándole a los zombies"** → `isRunning()` ahora se lee además de
   `isSprinting()`; las tareas de seguir se traban para que el combate no las robe.
3. **Resistencia que solo baja** → `WALK_RECOVERY = 0.01` por sweep; umbral `WINDED = 0.15`
   por debajo del cual se prefiere descansar a lootear.

**Archivo principal:** `ScenesRelationsAutonomy.lua` (+797 líneas). Review: PASS (un
WARNING por constante muerta, sin crashes ni regresiones).

**Pruebas:** P14–P18 en `TESTING-NOW.md`.
