# Sesión 09-08 — qué concluimos y cómo lo arreglamos

Este archivo es el cierre de la sesión del 09-08: lo que se **probó**, lo que se **descubrió**, y
el plan de arreglos con su orden. No repite lo que ya está en `TODO.md` — eso queda para después
a propósito. Acá solo está lo que se toca ahora y lo que hay que probar por lo que se tocó.

> Español porque lo leés con el juego abierto, igual que `TESTING-NOW.md` y `TEST-LOG.md`.

---

## 1. Lo que la ronda de pruebas dejó claro

| Prueba | Resultado |
|---|---|
| **B2** — mochila puesta | El equipar **funciona**: el log dice `LOOT ... wears the ...`, sin errores. Lo que falla es el **redibujado**. |
| **B2b** — cadáver | Quedó todo. No hay pérdida de inventario. Faltaba poder auditarlo. |
| **B4** — pánico | Ya no sube sostenido. Queda un **parpadeo** de un microsegundo al mirar de golpe a un NPC. |
| **A7** — ropa | Sin probar. Despriorizado por pedido tuyo. |
| Aserciones | `25 ok, 0 FAILED`. |

### Hallazgos de comportamiento reportados en juego

1. **El compañero no vuelve a seguirte** si huye y vos corrés **hacia** él.
2. **Se congela frente a una ventana** que él mismo abrió, estando ya dentro de la casa.
3. **Lootea a través de paredes**, muebles de otra habitación.
4. **Se sienta demasiado**, y en el suelo.
5. **Un NPC cerca te levanta del sofá.**

---

## 2. Las causas, verificadas contra el código

Ninguna de estas es una hipótesis. Cada una tiene el grep o el número que la prueba.

### 2.1 El miedo no te cuenta a vos

`friendsNear` leía solo `BanditZombie.CacheLightB`, que son NPCs. **Vos no estás en esa lista.**
El log lo mostraba crudo: `master=0.5 ... friends=0` — con vos a medio tile.

### 2.2 El término dominante del miedo ignora cuánta gente hay

Éste es el hallazgo central y lo subestimé la primera vez.

```
situacional = min(zombis, 6) × 6   +   término de proporción
                    ↑
        no mira amigos, ni grupo, ni nada
```

El miedo se estabiliza en `situacional / 0.4`. Con seis zombis el primer término solo da
`36 / 0.4 = 90`, que **cruza el umbral de 83 por sí solo**. Cinco NPC leales hombro con hombro
contigo contra seis zombis: huyen todos. Toda la calibración por proporción está muerta
exactamente en el caso para el que se escribió.

### 2.3 El refugio no distingue "llegué" de "me desplazaron"

`seekShelter` encola una ruta y `mood.sheltering` quedaba trabado. Cuando la ruta se **completa**
(caso normal: una ventana ya abierta a menos de 8 tiles, se resuelve en un solo barrido), la
cabeza de la cola deja de coincidir y se vuelve a encolar. Cada barrido. Para siempre.

**Eso es exactamente tu congelamiento frente a la ventana.** Y se desbugueó al matar al zombi
porque ahí el miedo bajó y el peldaño dejó de ser SURVIVE.

### 2.4 El refugio no pregunta si ya estás adentro

```
grep -c "indoors" ScenesRelationsThreat.lua  →  0
```

El módulo asume que un asustado está **afuera** y necesita entrar. Adentro no es inútil, es
dañino: `findWindow` prefiere una ventana ya abierta y `seekShelter` abre una cerrada, así que un
NPC asustado en una habitación segura camina a la pared y le abre un agujero.

### 2.5 El miedo no tiene percepción

```
grep -c "LosUtil" ScenesRelationsAutonomy.lua  →  0
```

Un zombi dentro de otra casa, detrás de dos paredes, asusta igual que uno en la misma habitación.
Mismo concepto faltante que el loot a través de paredes, pero en la capa de percepción.

### 2.6 El loot no verifica que llegó

`onComplete` corre cuando la tarea **termina**. Una tarea de Bandits nunca garantiza que
**llegó** — esa es R13. Por eso podía vaciar un mueble de otra habitación.

### 2.7 Sentarse era personalidad, no cansancio

Un quinto de los NPC tenía un umbral tan alto que se sentaban con el 20% de la barra gastada.

---

## 3. Descubrimientos que sobreviven a esta sesión

Esto es lo que hay que no volver a buscar.

### 3.1 `AdjacentFreeTileFinder` es vanilla y trae el primitivo del bloque B

```
pzserver/media/lua/shared/Util/AdjacentFreeTileFinder.lua
    Find :135    FindClosest :193    FindWindowOrDoor :231    FindWall :289
```

Es la biblioteca **del motor** para "en qué casilla me paro para usar esto, contando paredes".
`FindWindowOrDoor` es literalmente lo que el bloque B iba a reinventar. Hoy dependemos de
`BanditUtils.GetAccessSquare`, cuyo `canReachTo` Slayer dejó comentado — la causa medida de que
abandonen ~7 muebles por cada uno que abren.

**La trampa que lo escondía:** ambas librerías se declaran por asignación, no con `function`.
`grep "function Foo.Bar"` no encuentra ninguna. Grepear siempre el nombre pelado.

### 3.2 Sentarse en sillas es reimplementable sin copiar assets

El AnimSet de Slayer es un XML de 20 líneas que apunta a un clip **del juego base**:
`Bob_SatChair`, con `Bob_SatChairIn` y `Bob_SatChairOut` para entrar y salir. Escribimos el
nuestro con nuestro `BumpType` apuntando al mismo clip.

Bandits — lo único que tenés instalado — solo trae animaciones de suelo. Las de silla vienen con
The Ark y Week One. Por eso hoy solo se sientan en el piso: no es una decisión, es lo único que
existe en tu instalación.

Para encontrar la silla, Slayer usa `obj:getSprite():getProperties():has("Facing")`.

### 3.3 Descansar en un mueble sí es mecánicamente mejor

`ISRestAction` llama `setIsResting(true)`; `ISSitOnGround` **nunca** lo llama — verificado por
grep en todo el motor. Los números exactos no existen en Lua, son Java. La diferencia
silla/suelo la vamos a elegir nosotros, y eso queda escrito.

### 3.4 Lo del sofá probablemente no se puede arreglar

El mecanismo es `stopOnWalk` / `stopOnRun` / `stopOnAim`, en `true` por defecto en
`ISBaseTimedAction`, que ni `ISRestAction` ni `ISSitOnGround` sobreescriben. Pero el **disparador**
—qué hace que un `IsoZombie` cerca te ponga en combate— no está en Lua. Los flags solo son
escribibles en acciones que construimos nosotros, y la instancia que corre cuando vos te sentás no
es nuestra. **Verificado: no alcanzable desde Lua.**

---

## 4. El plan de arreglos

Dos revisiones encontraron que **cada pasada anterior introdujo defectos nuevos**. Por eso el
orden es por riesgo, no por valor.

### Mitad SEGURA — se arregla y se prueba ya

| # | Qué | Estado |
|---|---|---|
| S1 | **Restaurador del pánico.** El camino rápido puede morir después de haber suprimido y dejar el pánico apagado toda la sesión, porque `sweep` ya no escribe ese campo. Al morir tiene que restaurar el valor original. | a arreglar |
| S2 | **Umbral de sentarse.** Eliminado el "tipo perezoso" entero, no re-tarifado. Un umbral adentro, otro afuera. | hecho |
| S3 | **Log de qué ítems tomó**, no cuántos. Para que puedas cotejar el cadáver. | hecho |
| S4 | **`resetModel()` después de vestir.** Experimento, no arreglo: lo genuinamente nuevo es el **orden** — Bandits resetea antes de vestir, nosotros después. | hecho |

### Mitad RIESGOSA — con defectos severos confirmados

| # | Qué | Por qué es riesgoso |
|---|---|---|
| R1 | **El latch de reenganche** deja al compañero sin pelear. `disengaging` se evalúa antes que todo y el latch solo se limpia cuando el miedo baja — pero el miedo lo alimentan los zombis que él debería matar. Se traba hasta que vos matés la horda solo. | **el peor de todos** |
| R2 | **El término dominante del miedo** (2.2). Hay que hacerlo consciente de cuánta gente hay, y recalibrar. | alto |
| R3 | **El rechazo del loot borra el mueble para siempre.** Se marca al llegar, antes del rechazo. Números actuales: 67 abandonos contra 14 tomas, y el chequeo viejo nunca rechazó ni una vez en tres sesiones. Sumar un rechazo real delante de eso apaga el loot. | alto |
| R4 | **El chequeo de pared del loot es inerte.** El paso 2 ya garantiza estar a 0.7 de la casilla, así que el paso 3 pregunta si una casilla se ve a sí misma. La protección real venía del paso 2. | medio |
| R5 | **Las claves de reclamo usan flotantes.** Dos NPC en la misma ventana generan claves distintas, así que el reclamo nunca niega y el caso "me negaron el lugar" es inalcanzable. | medio |

### Cómo se arregla cada uno de la mitad riesgosa

- **R1** — el latch necesita un límite que no dependa del miedo. Un presupuesto de barridos: se
  engancha, fuerza OBEY unos pocos barridos, y se suelta pase lo que pase. Termina siempre.
- **R2** — dividir el término por baldosa entre la cantidad de gente, y bajar `FEAR_KEEP` para que
  reaccione rápido. Con `KEEP = 0.6` y umbral 83, cinco zombis tardan **30 segundos** en hacerlo
  huir; con `KEEP = 0.35` y umbral proporcional, **12 segundos**, con la misma calibración tuya.
- **R3** — desmarcar el mueble al rechazar, acotado por el contador de intentos que ya existe.
- **R4** — medir la línea contra la casilla **del mueble**, no contra la casilla de parada.
- **R5** — redondear las coordenadas de la ventana a baldosa entera antes de encolar.

---

## 5. Qué hay que probar por lo que se tocó

Reemplaza la ronda anterior. `TESTING-NOW.md` se reescribe con esto.

| # | Qué hacer | Pasa si |
|---|---|---|
| **P1** | Dale una mochila a un NPC y quedate mirándolo **sin alejarte**. | Se le ve puesta sin tener que descargar y recargar. Si no, mandame igual la línea `LOOT ... wears the ...`: significa que el redibujado en vivo **no se puede** desde Lua y hay que diseñar alrededor. |
| **P2** | Parate pegado a tus compañeros, sin zombis, y **mirá de golpe** a uno. | **Ni un parpadeo** del moodle de pánico. |
| **P3** | Dejá pasar una sesión larga y buscá `PANIC` en el log. | No aparece `fast suppression is OFF`. Si aparece, el pánico quedó apagado y hay que verlo. |
| **P4** | Lootea con un NPC y después matalo. | El log lista **qué** ítems tomó, y el cadáver coincide. |
| **P5** | Miralos cuando estén cansados. | Se sientan **solo** por cansancio. Ya no debería haber ninguna línea `the lazy sort`. |

Lo que **no** hay que probar todavía: huida, reenganche, y el loot con chequeo de pared. Esos
salen cuando se cierre la mitad riesgosa.

---

## 6. Ronda del 09-08 noche — el bolso no se usa nunca

### La evidencia, del log nuevo

```
LOOT David Murphy wears the Base.Bag_DuffelBag
LOOT David Murphy took 3 from 10616,10318 | carrying 10.9 / 8.0
LOOT David Murphy took 2 from 10639,10410 | carrying 11.1 / 8.0

stops searching -- full :  0
```

**Lleva 11.1 sobre una capacidad de 8.0 — 139% — con un bolso puesto, y nunca se detiene por
lleno.** Eso es exactamente lo reportado: "quedan muchas cosas por fuera del bolso, como si el NPC
guardara las cosas en el inventario general y no en el bolso".

### Por qué

En PZ **un bolso puesto es un contenedor SEPARADO**. `zombie:getInventory()` es el inventario
general y no crece ni un gramo cuando se equipa una mochila. `AddItem` sobre él nunca mete nada
en el bolso.

Y acá está la inconsistencia que lo dejó invisible: `Loot.CarryBudget` **sí** suma la capacidad
del bolso (`(base + bolso) × 0.7`), así que con una duffel el presupuesto es 18.2 mientras el
inventario real revienta a los 8. Por eso `stops searching -- full` sale **cero veces**: el
presupuesto cree que hay lugar en un contenedor donde nunca guardamos nada.

### Cómo se arregla

La ruta está verificada contra el motor:

```lua
bag:getItemContainer():AddItem(item)
```

`pzserver/media/lua/client/Tutorial/Steps.lua:1327` y
`pzserver/media/lua/shared/Items/SpawnItems.lua:151`.

Falta comprobar una cosa antes de escribirlo: si `Bandit.UpdateItemsToSpawnAtDeath` ve lo que está
dentro del bolso, o solo lo que está en el inventario general. De eso depende que las cosas caigan
al morir.

### Y la sobrecarga que pediste

Lo que pediste — estado de sobrecarga, daño, no poder correr, cansarse antes — es el incentivo que
hace que guardar en el bolso sea obligatorio y no cosmético. Va **después** de que guardar en el
bolso funcione: sin eso, la sobrecarga solo los castigaría por algo que no pueden evitar.

## 7. La "invencibilidad" y el daño por arma de fuego — una sola causa

Tres reportes, y el tercero explica los otros dos.

- "entre varios zombis a veces al revisar la vida tenía lo mismo y no le bajaba"
- "el estado de `safe` no cubre el daño por arma de fuego"
- "puede quedar inválido con su salud al 100% y le toca arrastrarse"
- "se ve la cara como comida por zombis"

**La hipótesis que las une: el daño por parte del cuerpo se lleva aparte de `getHealth()`.**

El panel lee `condition` contra `brain.health`, que es el máximo **de spawn** — David spawneó con
1.80, no con 1.00. Un mordisco mueve poco sobre 1.80, y el censo lo confirma: `hp=0.40` aparece
74 veces seguidas, una meseta larga. Se ve congelado sin estarlo.

Pero "inválido con la salud al 100%" no se explica con eso. Eso solo pasa si hay un modelo de
daño **por parte** — pierna destruida, cara comida — que el número global no refleja. Y encaja con
que `safe` bloquee el daño global pero no lo que se registra por zona.

Esto es exactamente el terreno del menú de salud y curación. **No se toca hasta entrar ahí**, tal
como pediste — pero queda escrito que los tres síntomas son probablemente uno.
