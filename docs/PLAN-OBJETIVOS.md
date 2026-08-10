# Objetivos y `GoAndDo` — plan de implementación

Cómo pasamos de una escalera que re-decide desde cero cada barrido a NPC con **un objetivo
principal y varios secundarios**, sin multiplicar la clase de bug que nos costó tres ciclos de
revisión esta semana.

> Español porque es un documento de diseño que discutimos vos y yo. El código y sus comentarios
> siguen en inglés.

---

## 0. La regla que gobierna todo lo demás

**Un objetivo se RECALCULA, no se RECUERDA.**

Los seis defectos que la revisión encontró esta sesión tienen la misma causa: **estado que
sobrevivió a su condición**.

| Latch | Qué hizo |
|---|---|
| `mood.sheltering` | quedó trabado; el NPC re-encolaba la ruta a la ventana para siempre |
| `mood.rejoining` | se limpiaba solo si bajaba el miedo, y el miedo lo alimentaban los zombis que él debía matar |
| `mood.wanting` | latch sin motor de re-entrada; mató la conducta de ropa entera |
| `mood.posture` | quedaba en `flee` fuera de rango y suprimía el idle |

Un sistema de objetivos **es** un sistema de latches. Construido ingenuamente, multiplica esto
por diez.

Por eso: el objetivo principal es una **función pura del mundo** —dónde estoy, dónde está el
jugador, qué hay cerca— evaluada cada barrido. Nunca un flag guardado. Lo único que persiste es
el **progreso** de una tarea en curso, jamás la decisión de tenerla.

Tu propio ejemplo lo pide así: *"si sale, ese será nuevamente su objetivo principal, seguirlo"*.
Eso es una función del mundo, no una bandera.

---

## 1. Contra el vaciado de la cola: NO una cola duplicada

Preguntaste si conviene una cola temporal duplicada. **No**, y por una razón que ya nos costó
caro: dos estructuras decidiendo qué hace el NPC es exactamente R6, el defecto donde `Threat` y
`Autonomy` decidían lo mismo con números distintos y se contradecían. Una segunda cola es esa
misma trampa con otra ropa.

### Lo que descubrí verificando, y que cambia el diagnóstico

Nuestro propio comentario en `assertFollow` dice que la tarea de seguimiento *"rastrea un
personaje en vez de una coordenada... la tarea sigue al jugador en lugar de caminar a donde el
jugador estuvo"*.

**Es falso.** `ZombieActions.Move` (`vendor/Bandits/mods/Bandits/42.20/media/lua/shared/ZombieActions/ZAMove.lua:9`)
hace `pathToLocation(task.x, task.y, task.z)` — una **coordenada fija**, capturada al arrancar.
Y los campos `tid` / `isPlayer` que `GetMoveTaskTarget` escribe en la tarea **no los lee nadie**:

```
grep -rn "task.tid\|task.isPlayer" vendor/Bandits/mods/Bandits/42.20/media/lua/  →  vacío
```

Son campos vestigiales. La tarea camina a donde estabas, no a donde estás.

**Entonces el vaciado no era gratuito: compensaba una tarea que se pone vieja.** El error no es
refrescar, es *cómo*: tirar la cola entera para refrescar un objetivo destruye todo lo demás que
el NPC estaba haciendo.

### La solución, en tres piezas

**1. Dejar que la tarea expire sola — SOLO para refrescar un objetivo que ya es correcto.**

Corrección, porque la primera versión de esta sección enunció esto como principio general y no lo
es. Hay que separar dos situaciones que no se parecen en nada:

| | Refrescar | Interrumpir |
|---|---|---|
| Qué pasa | el objetivo sigue siendo bueno, la coordenada envejeció | el objetivo cambió: hay un zombi encima |
| Ejemplo | seguir al jugador que se movió | estaba looteando y lo atacan |
| Urgencia | ninguna | inmediata |
| Herramienta | dejar expirar (`time=20`) | preempción |

Para **refrescar**, dejar expirar es correcto: nada está mal, solo queremos coordenadas frescas, y
vaciar la cola entera para conseguirlas destruye todos los secundarios. Ese bucle ya existe —cola
vacía, el programa corre, emite seguimiento nuevo— y solo hay que dejar de interrumpirlo.

Para **interrumpir**, esperar es inaceptable y hay que preemptar. Eso NO se hace vaciando: se hace
con las primitivas de abajo.

**1b. Las cuatro primitivas, todas verificadas en Bandits 42.20**

Nunca hizo falta una segunda cola: el framework ya trae cirugía sobre la que tiene.

| Primitiva | Qué hace | Para qué |
|---|---|---|
| `Bandit.AddTaskFirst` (`Bandit.lua:300`) | inserta al frente | "hacé esto YA" |
| `Bandit.RemoveTask` (`Bandit.lua:361`) | saca **solo la cabeza** | cancelar la acción en curso conservando el resto |
| `Bandit.UpdateTask` (`Bandit.lua:352`) | reemplaza la cabeza en el lugar | acortar el `time` de lo que se está haciendo |
| `Bandit.ClearTasks` (`Bandit.lua:369`) | vacía, conservando `lock == true` | **solo** cambio de objetivo principal |

`Bandit.UpdateTask` es exactamente la idea de "que la tarea de lootear dure menos cuando cambia el
ambiente": saca la cabeza y pone otra igual con menos tiempo.

**1c. Urgente contra no urgente**

La distinción sale del propio ejemplo del usuario y decide qué primitiva se usa:

- **No urgente** — se oye un zombi afuera, todavía no es una amenaza. `Bandit.UpdateTask`
  acortando el tiempo: termina el cajón en 3-5 segundos y sigue. No se ve roto.
- **Urgente** — algo dentro del rango de combate. `Bandit.RemoveTask` y después
  `Bandit.AddTaskFirst`. Corta la animación, y eso está bien: un superviviente al que muerden
  suelta lo que tiene en la mano.

**1d. La latencia, que es el problema real de todo esto**

El barrido corre en `Events.EveryOneMinute` ≈ **6 segundos reales**. Para lo urgente es
inaceptable: un zombi puede morder tres veces en ese hueco.

La solución ya está probada en este mod y es el patrón de `ScenesRelationsPanic.lua`: **decidir
lento, aplicar rápido.** El barrido caro sigue en su cadencia; un handler barato en la cadencia
rápida —el mod ya registra `OnTick` y `OnPlayerUpdate`— solo pregunta "¿hay algo dentro del rango
de combate y la cabeza de la cola no es pelear?" y preempta. Sin recorrer caches, sin asignar
memoria, sin loguear salvo que algo cambie.

**2. El barrido interviene cuando cambia el OBJETIVO, no para refrescar.** Vaciar es legítimo
cuando el objetivo principal cambia —huir gana sobre lootear— e ilegítimo como mecanismo de
refresco. Regla: **se vacía en transición de objetivo, nunca por reloj.**

**3. Cuando haya que preservar algo, usar el seam que Bandits ya trae.** `Bandit.ClearTasks`
(`Bandit.lua:369`) **no borra todo**: conserva las tareas con `task.lock == true`.

```lua
for _, task in pairs(brain.tasks) do
    if task.lock == true then table.insert(newtasks, task) end
end
```

Ya existe un marcador de "no me borres". Y `brain.tasks` es una tabla Lua común, así que también
podemos filtrar por dueño nosotros mismos.

**4. Etiquetar por dueño.** Cada tarea que emitimos lleva quién la produjo:

```lua
task.srGoal = "follow"   -- o "loot", "shelter", "rest"
```

Reemplazar el seguimiento pasa a ser "sacá las tareas de `follow` y poné esta", no "borrá todo".
Un objetivo solo puede tirar **sus propias** tareas. Y como bonus, el log puede decir de quién
era la tarea que se descartó, que hoy es invisible.

---

## 2. `GoAndDo` como átomo

`SR.Move.GoAndDo(zombie, point, task, opts)` ya devuelve `tasks, arrived` y **nunca** devuelve el
movimiento y la acción juntos: o caminás, o actuás. Esa es la forma correcta y hay que
generalizarla.

**La trampa, escrita para que nadie la repita (R13b):** una función que devuelve trabajo en
cuotas **solo es segura donde algo la vuelve a invocar con la cola vacía**. Un programa de
Bandits tiene ese motor. Un barrido de `Events` detrás de un latch **no lo tiene** — y eso mató
la conducta de ropa entera el 08-08.

Así que la regla de uso: **`GoAndDo` se llama desde un programa, o desde un barrido que se
re-invoque incondicionalmente.** Nunca desde detrás de un latch.

---

## 3. El modelo de objetivos

```
objetivo principal   = f(mundo)          ← recalculado cada barrido, jamás guardado
objetivos secundarios = lo que el programa encola cuando la cola está vacía
```

La escalera actual (`idle → errand → obey → fight → survive`) **ya es** el selector de objetivo
principal. Lo que le falta es que los secundarios sigan existiendo mientras el principal manda.

Tu ejemplo, traducido:

| Situación | Principal | Secundarios |
|---|---|---|
| En clan, jugador afuera | seguir al jugador | pegarle a lo que lo ataque |
| En clan, ambos en una casa | quedarse en el edificio | lootear, vigilar puertas, descansar si está cansado |
| Rodeado | salir por la ventana más despejada | pelear con lo que se le atraviese |

El cambio de "seguir" a "quedarse" cuando ambos entran a un edificio, y su vuelta a "seguir"
cuando el jugador sale, es exactamente lo que la regla de la sección 0 hace gratis: se recalcula.

---

## 4. Entrar y salir de un edificio

Tu orden de prioridades, con lo que falta para implementarlo.

```
1. Puerta          → 1.1 con llave: siguiente puerta exterior → romper la ventana más cercana
                     1.2 sin llave: entrar/salir normal
2. Ventana         → última opción
```

Para salir: la puerta exterior **más cercana al jugador**, porque casi siempre está siguiéndolo.

**El hueco concreto: Bandits no tiene ninguna acción de puerta.** Tiene `ZAOpenWindow`,
`ZASmashWindow`, `ZAClimbFence`, `ZAUnbarricade` — ninguna de puerta. Ese es el primer ladrillo y
hay que escribirlo.

**Lo que no hay que inventar:** el primitivo de "en qué casilla me paro para usar esta puerta o
ventana" es vanilla —
`pzserver/media/lua/shared/Util/AdjacentFreeTileFinder.lua`, `FindWindowOrDoor` en la línea 231.

Los casos especiales (horda, señuelo, salir por atrás) van a `TODO.md`, como pediste.

---

## 4b. Cómo bajar el costo de revisar

`pz-review` encontró defectos reales tres veces esta semana, incluida una en un commit que ya
estaba pusheado. No es negociable. Pero cuesta ~100k tokens por pasada, y **la mayor parte se
gasta re-derivando hechos que un grep contesta**.

Separando los hallazgos de esta sesión por naturaleza:

| Hallazgo | ¿Lo puede encontrar una herramienta? |
|---|---|
| `mood.sheltering` / `rejoining` / `posture` trabados | **Sí** — escritura de un flag sin ruta de limpieza |
| tarea con `time=20` vive 0.33 s, contra un throttle de 800 ms | **Sí** — es aritmética sobre una constante |
| cita a `vendor/` sin carpeta de versión | **Sí** — patrón de texto |
| `local` usado por encima de su declaración | **Sí** — es exactamente lo que hace `luacheck` |
| `pcall` que se traga un error sin loguear | **Sí** — heurística de forma |
| ¿este bucle termina? | No |
| ¿el llamador tiene motor de re-entrada? | No |
| ¿este umbral es el correcto? | No |

Las cinco primeras son mecánicas y hoy las paga un modelo. **`tools/lint.sh` son 51 líneas y solo
mira sintaxis e ids; `luacheck` ni siquiera está instalado**, pese a que el bug de "un `local`
declarado abajo se vuelve un global nil" mató una conducta entera el 08-08.

Propuesta: `tools/audit.py`, con estos chequeos, elegidos porque cada uno corresponde a un defecto
que **realmente ocurrió**:

1. **Auditoría de latches.** Toda escritura `mood.X = <truthy>` sin un `mood.X = nil` en el mismo
   archivo. Habría marcado cuatro de los seis defectos de la semana.
2. **Vida real de las tareas.** Toda tarea encolada con `time = N`, convertida a segundos con la
   fórmula del motor (`1 / ((fps + 0.5) * 0.01666667)` por frame ≈ 60 por segundo), contra la
   cadencia del código que la consulta. Habría cazado el defecto 1 del revert al instante.
3. **Puntos de vaciado de cola.** Todo `ClearTasks` / `AddTaskFirst` con su dueño.
4. **Citas a vendor sin versión.** El árbol trae 42.12 … 42.20 en paralelo.
5. **`luacheck`**, para globales no declarados y orden léxico.

Y el cambio que de verdad baja el costo: el brief de `pz-review` empieza con *"corré
`tools/audit.py` y no vuelvas a derivar lo que reporta"*. Deja de gastar tokens en lo grepeable y
los gasta en lo que solo un modelo puede contestar: terminación, motores de re-entrada, y si el
número elegido tiene sentido.

**Automatizar el gate, no la revisión.** La revisión es una llamada a un modelo y no va en un hook.
Lo que sí va en un hook de `pre-push` es `lint.sh` + `audit.py`: si fallan, no sale. La revisión
sigue siendo un paso delegado, pero con un brief mucho más chico.

## 4c. El paso 3 se descartó, y la razón vale más que el paso

Se escribió, se revisó y **no se commiteó**. La revisión encontró que la premisa era falsa, y lo
verifiqué yo mismo contra el motor.

**Lo que creíamos:** "un programa de Bandits solo corre con la cola vacía, así que un NPC tres
tareas adentro nunca se entera del zombi". Es la frase que abre `ScenesRelationsAutonomy.lua` y
es cierta **para casi todo, menos para combate**.

**Lo que hace Bandits en realidad:**

```lua
elseif combat then
    if not BanditBrain.HasTaskTypes(brain, {"Smack", "Push", "Equip", "Unequip"}) then
        Bandit.ClearTasks(bandit)      -- se limpia la cola A SÍ MISMO
```
`vendor/Bandits/mods/Bandits/42.20/media/lua/client/BanditUpdate.lua:1210-1212`

`ManageCombat` corre **cada tick de Bandits**, no cada 800 ms ni cada 6 segundos, y **vacía la
cola por su cuenta** para meter el ataque. "Está looteando y lo muerden, tiene que soltar el
cajón" nunca estuvo bloqueado por la cola. Ya funcionaba.

**Y nuestro interruptor era activamente dañino.** Cancelábamos a `ENGAGE_RANGE = 4`, pero Bandits
solo pelea a `meleeDist = isOutside and 2.6 or 1.2` (`BanditUpdate.lua:961`). Entre 1.2 y 4
—adentro de una casa, que es donde se lootea— cancelábamos una tarea que el framework **no** iba a
reemplazar por nada: sin combate, sin loot, sin movimiento, hasta el próximo barrido de un minuto.
Cada 800 ms, con una línea de log cada vez. **Hasta 60 segundos de parálisis total** donde antes
había "termina el cajón en 3 segundos y vuelve a decidir".

### Qué se aprende, y qué queda

1. **La latencia de 6 segundos no es un problema de combate.** Lo es de todo lo demás —decidir
   huir, decidir seguir— pero el combate ya lo resuelve upstream a velocidad de tick.
2. **Antes de acelerar una decisión, hay que verificar que la decisión lenta sea la que manda.**
   Acá la lenta no mandaba: mandaba una rápida que ya existía y que no habíamos leído.
3. **Un rango de interrupción tiene que ser MENOR o igual al rango en que algo lo reemplaza.**
   Cancelar más lejos de lo que el reemplazo alcanza crea una banda muerta. Si alguna vez vuelve
   a hacer falta interrumpir, ese es el invariante.

**Hueco de upstream, anotado y no arreglado:** `ManageEndurance` encola cinco tareas
`{action="Time", anim="Exhausted", time=200, lock=true}` (`BanditUpdate.lua:439-444`) — unos 16
segundos de indefensión que ni `Bandit.ClearTasks` puede quitar por el `lock`, y que corren
**antes** de `ManageCombat`. Un NPC exhausto no se defiende. No es nuestro y no se toca, pero
explica muertes que parecían inexplicables.

## 5. El orden

Cada paso deja algo probable en juego. No se encadenan a ciegas.

Reordenado el 10-08, después de que el intento de hacer el 3 solo tuviera que revertirse. Cada
fila dice qué se delega y qué tiene que ser verdad para poder cerrarla — para que el brief del
subagente salga de acá y no haya que redactarlo cada vez.

| # | Qué | Estado | Se delega a | Terminado cuando |
|---|---|---|---|---|
| **0** | `tools/audit.py` + `luacheck` (sección 4b) | ⬜ | `pz-lua` (es tooling, no mod) | los 5 chequeos corren y el brief de review los cita |
| **1** | Revertir el vestir la mochila | ✅ `f4839cf` | — | el cadáver trae UNA mochila |
| **2** | Etiquetar **todos** los productores de tarea con `srGoal` | ⬜ | 1 escritor, mecánico | `grep -c srGoal` cubre loot, refugio, descanso, idle y follow |
| **3** | ~~Corte de interrupción rápida~~ | ❌ **descartado** | — | la premisa era falsa, ver 4c |
| **4** | Re-aterrizar la cola que sobrevive | ⬜ | 1 escritor + review | Threat sabe que una cabeza ajena no es ruta perdida; Loot distingue "interrumpido" de "no llegué" |
| **5** | Modelo de objetivos ppal/secundarios | ⬜ | 1 escritor + review | ningún `mood.*Goal` guardado; todo derivado |
| **6** | Acción de puerta + orden entrar/salir | ⬜ | `pz-research` → 1 escritor | entra por la puerta antes que por la ventana |
| **7** | Persistencia `scenesCarry` → `permaInv` | ⬜ | `pz-research` → 1 escritor | desbloquea guardar en el bolso Y la sobrecarga |

**Qué cambió respecto de la primera versión, y por qué.** El 3 original —dejar de vaciar la cola—
se intentó solo y hubo que revertirlo: sin `srGoal` en todos lados, Threat leyó una cabeza ajena
como ruta perdida y acumuló tareas, y una interrupción de seguimiento hizo que Loot registrara un
rechazo falso que borra el mueble a los tres. **La cola que sobrevive es una consecuencia del
etiquetado, no un paso previo.** Por eso ahora el etiquetado es el 2 y la cola es el 4.

El 3 (interrupción rápida) se adelantó porque el barrido decide cada 6 segundos, y ningún modelo de
objetivos se siente vivo encima de eso — un NPC que tarda seis segundos en notar que lo muerden no
parece que tenga objetivos, parece tildado.

Guardar en el bolso bajó al 7: resultó ser un cambio de **persistencia**, no de looteo. El
inventario vivo es una vista que se pierde al despawnear.

**El modelo de miedo se arregla dentro del 6**, no antes: su defecto conocido —el término
dominante ignora cuánta gente hay— es el mismo problema de "el principal no mira el contexto".

---

## 6. Cómo sabremos que funciona

Sin esto, "mejoró" es una opinión.

| Señal en el log | Hoy | Meta |
|---|---|---|
| `gives up ... could not get there` | 96 por sesión | menos de 20 |
| `stops searching -- full` | 0 (nunca, con el bolso puesto) | mayor que 0 |
| `carrying` sobre capacidad | 139% | nunca sobre 100% |
| distancia al seguir | siempre "gap opening" | estable bajo 6 tiles |
| tareas descartadas por barrido | 2 por ciclo de oscilación | 0 salvo transición de objetivo |
