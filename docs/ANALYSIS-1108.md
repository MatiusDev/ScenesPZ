# Análisis de sesión 11-08 — Health panel, Pathfinding, Panic, WOUND

## Contexto para otro agente

Este documento resume el desarrollo aplicado en las sesiones del 10-08 y lo que se
encontró en la prueba del 11-08. El otro agente debe leerlo ANTES de proponer cambios.

### Módulos activos en esta build

| Módulo | Archivo | Qué hace |
|---|---|---|
| Autonomía | `ScenesRelationsAutonomy.lua` (2390 líneas) | Ladder, follow locks, watchdog con ClimbFence/OpenWindow/SmashWindow/ToggleDoor |
| Pathfinding | `ScenesRelationsPathfinding.lua` (198 líneas) | `ChooseRoute`: chequeo preventivo de línea directa antes de caminar |
| Move | `ScenesRelationsMove.lua` (736 líneas) | `WhatBlocks`, `FindOpening`, `GoAndDo`, `classify` (con `BLOCK_WINDOW`) |
| Health | `ScenesRelationsHealth.lua` (390 líneas) | Panel de partes del cuerpo (17 partes), usa API real del motor |
| Wounds | `ScenesRelationsWounds.lua` (954 líneas) | Climb watcher 200ms, glass cuts con body parts del motor, bleeding |
| Panic | `ScenesRelationsPanic.lua` (283 líneas) | Supresión de pánico + spike detector |

### Lo que se construyó en las sesiones 10-08

1. **Body parts**: se confirmó que `getBodyDamage()`, `BodyPartType.*`, `bitten()`,
   `deepWounded()`, `scratched()`, `bleeding()`, `haveGlass()`, `setBleedingTime()`,
   `addVisualBandage()` SON llamables en `IsoZombie`. Bandits ya los usa en
   `ZASmack.lua:358` y `ZABandage.lua:50`. Nuestro `Wounds.lua` anterior decía
   que no existían — estaba equivocado.

2. **Health panel**: reescritura completa. Panel de dos columnas: izquierda con 17
   partes del cuerpo + puntos de colores, derecha con detalles de la parte seleccionada.
   Botón de vendaje por parte. Usa API real del motor (`ISHealthPanel.lua` verificada).
   Métodos verificados con grep: `bitten():683`, `isDeepWounded():234`, `scratched():631`,
   `bleeding():732`, `haveGlass():844`, `getBandageLife():773`, `getBurnTime():246`,
   `getFractureTime():267`, `isInfectedWound():297`, `stitched():523`,
   `getSplintFactor():523`, `getAdditionalPain():691`, `setBleedingTime(0):198`.

3. **Wounds glass damage**: `applyGlassCut` ahora usa body parts del motor:
   `setBleedingTime(10)`, `setHaveGlass(true)`, 5% `generateDeepShardWound()`.
   Cae en nuestro `wound.bleeding` si `getBodyDamage` no responde.

4. **ClimbFence**: 4 intentos fallidos documentados en git log. El actual (`7fe4061`)
   usa `setParams(state, dir)` + `changeState(state)` con dirección `IsoDirections`.
   JavaDoc confirma la firma `setParams(IsoGameCharacter, IsoDirections)`.
   **Nunca se ha confirmado que funcione en `IsoZombie`** — cero líneas de
   "changeState(ClimbOverFence)" en los logs.

5. **Pathfinding ChooseRoute**: detecta obstáculos en la línea directa ANTES de
   caminar. Para rejas (`hop`/`tall`), rutea al tile de la reja directamente.
   Para edificios (`door`/`window`), delega en `FindOpening`.

6. **Window types**: `classify` detecta ventanas (`BLOCK_WINDOW`). Watchdog: primer
   intento `OpenWindow`, reintento `SmashWindow`. Cooldown de 8 sweeps.

---

## Análisis de la prueba 11-08 (console.txt, 13733 líneas)

### 1. PANIC spike #1 — stat=14 en frame 191

```
f:1   TLOU| companion requested at 10720,10196,0 after 1 ticks
f:191 PANIC spike #1 detected | stat=14 despite suppression active
```

**Causa**: el NPC companion spawnea en frame ~1. El motor detecta un `IsoZombie`
cerca del jugador y aplica un bump de pánico directo (Java-side). Nuestra supresión
lo clampa en el tick siguiente, pero el spike se registra en el sweep. Stat=14 es
bajo — no llega a activar el moodle visible (que requiere ~25-30).

**Conclusión**: comportamiento esperado. El spike detector funciona correctamente.

### 2. PATHFINDING — bucle de ruteo en rejas

El NPC 10289607 rutó **23 veces** a rejas en ~17 segundos (frames 28277-35564):

```
ROUTE 10289607 | blocked by hop at 10703,10205 -- routing to fence crossing
ROUTE 10289607 | blocked by hop at 10703,10205 -- routing to fence crossing
ROUTE 10289607 | blocked by hop at 10703,10205 -- routing to fence crossing
... (3 veces mismo tile)
ROUTE 10289607 | blocked by tall at 10695,10199 -- routing to fence crossing
... (6 veces)
ROUTE 10289607 | blocked by hop at 10703,10199 -- routing to fence crossing
... (4 veces)
ROUTE 10289607 | blocked by hop at 10703,10198 -- routing to fence crossing
... (2 veces)
```

**El bucle**: `ChooseRoute` detecta reja → `assertFollow` queuea ROUTE Move al tile
de la reja → NPC camina al tile → follow se re-evalúa → `ChooseRoute` detecta la
misma reja otra vez → otro ROUTE Move → infinito.

El `obstacleAttempts` cooldown (8 sweeps) está keyeado por el tile de la reja. Pero
el PLAYER se está moviendo, así que el NPC sigue al player a través de diferentes tiles
de reja, cada uno con su propio cooldown. Ningún cooldown se activa lo suficiente.

**Nunca intentó trepar** — cero líneas de "changeState(ClimbOverFence)" o
"changeState(ClimbOverWall)". El watchdog NUNCA disparó para rejas porque
`ChooseRoute` lo intercepta antes. El ROUTE Move camina al tile, el follow dispara
de nuevo, y el ciclo se repite.

**El NPC prefirió rodear**: cuando no había ROUTE (cooldown activo en algún tile),
el motor encontró una ruta alrededor y el NPC dio toda la vuelta.

### 3. BLOQUEO al caminar — stuck on solid

```
AUTO Wyatt Watson | stuck on Move@10710,10190 -- blocked by solid
    -- routing to the door at 10718,10194 (door locked) | 2.9 tiles, 234 units
```

El watchdog SÍ funcionó para `solid`: detectó el bloqueo, encontró una puerta
(locked), y rutó. Pero la puerta estaba locked — el NPC no puede abrirla. El
watchdog hizo su trabajo; el problema es que la puerta no se puede abrir.

### 4. WOUND — funciona, NO validado en Health panel

```
WOUND ready -- ... climb watcher every 200 ms, both directions
```

El módulo cargó. No hubo cortes de vidrio en esta sesión (el NPC no cruzó ventanas
rotas). El usuario no pudo validar si la herida aparece en el panel de Health.

### 5. Ventanas que no abren — NO probado

El usuario no encontró una ventana fija para probar el ciclo OpenWindow→SmashWindow.

### 6. Health panel — NO se parece al del jugador

El panel actual es una lista de texto con puntos de colores. El del jugador es un
diagrama corporal gráfico (`ISBodyPartPanel`). **No podemos usar `ISHealthPanel`
directamente** porque está diseñado para `IsoPlayer` y requiere `ISMedicalCheckAction`.

Fotos de referencia en `caps/`:
- `player-health-menu.png` — panel del jugador sano
- `player-health-menu-injuried.png` — panel del jugador herido
- `npc-health-menu.png` — nuestro panel actual (lista de texto)

---

## Recomendaciones para el otro agente

### Urgente — arreglar el bucle de ruteo de rejas

`ChooseRoute` está causando más problemas de los que resuelve. Cada ROUTE Move al tile
de la reja genera otro ciclo de detección. **Posible fix**: cuando `ChooseRoute`
detecta `hop`/`tall`, en vez de queuear un ROUTE Move, debería disparar directamente
el climb (el watchdog ya tiene esa lógica). O el `obstacleAttempts` debería keyearse
por un radio más amplio, no por tile exacto.

### Urgente — el climb nunca se ejecuta

El método `setParams+changeState` con dirección `IsoDirections` nunca ha sido
confirmado en juego. Cero líneas de log. **Posible fix**: probar directamente en el
watchdog sin pasar por ChooseRoute. O buscar alternativas (el motor `climbOverFence`
del jugador, teleport después de la animación).

### Health panel — rediseñar con diagrama corporal

El panel de texto con 17 líneas no es lo que el usuario pidió. Quiere algo parecido
al `ISHealthPanel` del jugador. Opciones:
1. Usar `ISHealthPanel:new(zombie, ...)` directamente (requiere verificar si acepta
   IsoZombie)
2. Dibujar un diagrama simplificado con `drawTexture` y zonas clickeables
3. Usar `ISBodyPartPanel` si está disponible

### Follow — ambas condiciones importan

El usuario pide que el NPC siga si: (a) el jugador corre, O (b) se aleja mucho con
zombies cerca. Hoy `assertFollow` solo considera distancia + sprint/trote. Agregar
el contexto de zombies (`threats > 0`) a la decisión de follow.
