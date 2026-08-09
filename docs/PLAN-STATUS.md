# Qué probar ahora

Una sola página. Se reescribe cada vez que una etapa abre o cierra. Si esta página y
cualquier otra se contradicen, ésta es la que está vieja — arreglala.

> **Nota de idioma.** Este archivo va en español porque es el que vos usás mientras jugás.
> Todo el resto — código, comentarios, planes, commits — sigue en inglés.

Hoja de ruta completa: [`docs/plans/README.md`](plans/README.md).

---

## Cómo vamos a trabajar de ahora en adelante

Un bloque a la vez. Cada bloque son 2–3 cosas que comparten causa, no 12 sueltas. No abrimos
el siguiente hasta que el actual pase. Pediste esto y tenías razón: la corrida del 04-08 dejó
1.422 líneas de log y **una sola causa** explicaba cuatro de los síntomas.

---

## Ya confirmado — no lo repitas

| Qué | Evidencia |
|---|---|
| Memoria durable entre descargas de celda | corrida 03-08 |
| La rueda de interacción | *"ya se comporta mejor"* |
| Corte con vidrios rotos | `cut on broken glass \| 1.80 -> 1.55` |
| Arma silenciosa adentro de una casa | 5 × `goes quiet indoors` — **nunca había disparado** |
| Sentarse dejó de ser constante | *"si se sientan, y lo hacen menos seguido que antes"* |
| Cast out / expulsar | *"esto funciona correctamente"* (prueba 12) |

---

# BLOQUE A — segunda vuelta (05-08 noche)

## Qué pasó en tu corrida

| # | Reportaste | Veredicto |
|---|---|---|
| A0 | pasan | ✅ `ASSERT ---- 10 ok, 0 FAILED ----` en el log. El motor tiene la forma que el código cree, así que todo lo demás fue cableado nuestro. |
| A1/A2 | siguen loteando desde el punto | ❌ confirmado, y era un patrón, no un bug suelto |
| — | "cogen un montón de cosas que no sirven" | ❌ confirmado con aritmética: John James pasó de `carrying 0.2` a `6.3` en **3 ítems**. El presupuesto es 5.6. Un cajón malo termina su vida de saqueador. |
| A3/A4 | recoge la mochila, no se la pone, no queda en el cadáver | ❌ confirmado, y son **dos** fallos distintos |
| A5 | "sí aparecían ítems" | ⚠️ el log muestra 3 × `got N item(s) back after a respawn` — `Restore` funciona. Pero lo que viste en el cadáver puede ser el botín aleatorio de Bandits, no lo que recogió. Se vuelve a medir. |
| A6 | — | ✅ 6 × `stops searching -- full`. La línea dice por qué. |

## La causa de A1, que es la más importante de toda la sesión

No era la casilla adyacente. Era **el orden de la cola**.

`Loot.Search` encolaba las dos cosas juntas:

```lua
if dist > 0.9 then tasks[#] = GetMoveTask(...) end
tasks[#] = { action = "ScenesLoot", x = spot.x, y = spot.y }
```

Una tarea de movimiento en Bandits garantiza que **terminó**, nunca que **llegó**. Camino
bloqueado, puerta, empujón de un zombi, o la escalera de amenaza vaciando la cola: todo eso
termina el movimiento antes de tiempo — y la tarea siguiente se ejecutaba igual, leía sus
coordenadas y vaciaba un ropero al otro lado del cuarto.

**Slayer nunca tuvo este bug porque nunca escribe una cola que no puede verificar.**
`BWOAPrograms.GoAndDo` en The Ark devuelve el movimiento **o** la acción, jamás las dos. Un
programa solo corre con la cola vacía, así que eso sale gratis: camina → cola vacía → el
programa corre otra vez → ahora sí está al lado → actúa. La distancia se mide **al llegar**,
no se predice.

Esa es la plantilla que pediste, y quedó escrita como **R13** en `docs/CODE-REVIEW-RULES.md`.

## Qué toqué esta vez

- `Loot.Search` y `Loot.FetchBag`: un paso a la vez, patrón `GoAndDo`.
- La casilla se marca "ya revisada" **al actuar**, no al planear. Antes, un mueble al que nunca
  llegó quedaba como hecho.
- Tope de 3 intentos por mueble: sin callback de fallo de ruta, un objetivo inalcanzable se
  elegía para siempre.
- `LosUtil.lineClearCollide`: ya no lotea a través de una pared.
- `BanditUtils.GetAccessSquare` en vez del de vanilla — es de Slayer, recibe al bandido y
  devuelve el vecino libre **más cercano a él**, descartando los que tienen pared de por medio.
- Filtro de lo que vale la pena: comida (no veneno), armas, drenables (vendas), bebida, bolsos.
  Y ningún ítem que por sí solo se coma lo que queda del presupuesto.
- `WearBag` ahora reconstruye la lista de muerte y **saca el bolso del inventario suelto** — si
  no, salía duplicado o no salía.
- La acción se **niega** a lotear a más de 2 tiles y lo dice en el log.

### Y una segunda tanda, 08-08 de noche

- **Un solo primitivo caminar-luego-actuar**: `SR.Move.GoAndDo` (`ScenesRelationsMove.lua`),
  copiado de `BWOAPrograms.GoAndDo` de The Ark. Antes esa misma decisión estaba escrita a mano
  en cuatro lugares y el mismo bug había aparecido en dos. Ahora `Loot.Search`, `Loot.FetchBag`
  e `Idle.goGet` la comparten.
- **Bug encontrado en revisión, antes de que lo probaras.** `Idle.goGet` no tiene programa de
  Bandits detrás: corre desde un barrido `EveryOneMinute` con un candado `mood.wanting` que
  existía justo para impedir la segunda llamada. Encolaba la caminata y nunca el `PickUp` — el
  comportamiento de ropa idle quedaba muerto en silencio. Arreglado: el barrido vuelve a llamar
  a `goGet` con la cola vacía, con tope de 3 intentos.
- **Bandits y Week One actualizados** (08-06 y 08-07). Las citas `file:line` ahora incluyen la
  carpeta de versión: `vendor/` trae 42.12 … 42.20 en paralelo y el juego carga solo la que
  coincide con el build. `GetAccessSquare` está en :1056 en 42.20 y en :1039 en 42.18.
- 3 aserciones nuevas (19 en total).

## Cómo lo probás — segunda vuelta

| # | Qué hacer | Pasa si |
|---|---|---|
| **A0** | Buscá `ASSERT` en `console.txt`. **Antes que nada.** | `ASSERT ---- 24 ok, 0 FAILED ----`. Si algo dice `FAIL`, pará y mandámelo. |
| **A1** | Entrá a una casa con un compañero y miralo. | **Camina hasta cada mueble** y lo abre parado al lado. |
| **A2** | Buscá `LOOT refused` en el log. | **No aparece ni una vez.** Si aparece, la cola se sigue rompiendo y ahí está la prueba. |
| **A3** | Tirá una mochila al piso cerca. | La levanta y **se la pone** (se ve en el modelo). Log: `LOOT ... now carries a ...` |
| **A4** | Matalo después de que se la puso. | La mochila está en el cadáver, **una sola vez**. |
| **A5** | Dejalo lotear una casa entera. | Abre más de 5–6 muebles. Lo que agarra es útil: comida, vendas, armas — no ropa. |
| **A6** | Alejate hasta que desaparezca, volvé, matalo. | Suelta lo que recogió. |
| **A7** | Tirá una prenda al piso cerca de un NPC **libre** (no compañero) y esperá 2–3 minutos de juego. | Camina, la levanta y se la pone. Log: `IDLE ... wants ...` seguido de que se la ponga. **Si ves `IDLE ... gave up on ...` repetido, el arreglo de esta noche no funcionó** — mandámelo. |

---

## Tanda 09-08 — mochila que se ve, mochila que sirve, y dejar de tenerte miedo

Tu corrida del 09-08 pasó A0 (19/19) y A2 (**cero** `LOOT refused`). Lo que el log dijo y vos
no podías ver: **no dejan de lootear por estar llenos.** Cero paradas por `full`. Lo que hay
son **111 × `gives up on X,Y -- could not get there in 3 tries`** contra 15 muebles abiertos.
No llegan. Y esa es la misma causa de que se traben en puertas y ventanas — queda para el
bloque siguiente, que es el grande.

Lo que sí entró ahora:

- **La mochila ahora se ve.** No era el modelo: `ApplyVisuals` ya llama `resetModel()`
  (`Bandit.lua:280`). Era que la mochila entraba a la lista visual pero **nunca se equipaba** —
  Slayer dejó comentada la línea que lo hace (`Bandit.lua:249`). La ponemos nosotros, con
  `canBeEquipped()` y no `getBodyLocation()`, porque vanilla resuelve ese caso exacto así en
  `ISInventoryPaneContextMenu.lua:1690`.
- **La mochila ahora sirve.** Antes no daba **nada** de capacidad: el presupuesto salía del
  inventario principal, y en PZ una mochila es un contenedor aparte. Ahora
  `Loot.CarryBudget` le suma `getItemContainer():getMaxWeight()`, así que un framepack de 35
  rinde más que una escolar de 15. Cadena verificada en `FenrisScenario.lua:409`.
- **Tus propios NPC ya no te dan miedo.** Un Bandit *es* un `IsoZombie`, así que el modelo de
  pánico del motor los contaba como horda. Slayer escribió el arreglo y lo dejó apagado
  (`BanditPlayer.lua:132`, `if true then return end`). El nuestro es propio, no toca el suyo.
- **Kit de prueba: las 56 mochilas equipables del juego base**, generadas desde
  `container.txt`, no escritas a mano.
- 5 aserciones nuevas (**24** en total).

| # | Qué hacer | Pasa si |
|---|---|---|
| **B1** | Personaje nuevo. Mirá el inventario. | Están las 56 mochilas + pistola. Log: `test kit given -- 58 of 58 items`. |
| **B2** | Dale una mochila a un NPC y **quedate mirándolo**, sin alejarte. | **Se le ve puesta en la espalda al instante.** Antes solo aparecía si se despawneaba y volvía. |
| **B3** | Dale una `Bag_CraftedFramepack_Large3` (capacidad 35) a uno y una `Bag_Schoolbag` (15) a otro. Que looteen la misma casa. | El del framepack aguanta bastante más antes de `stops searching -- full`. La línea de log trae `carrying X / Y` — **Y tiene que ser distinto entre los dos**. |
| **B4** | Parate pegado a tus compañeros, sin zombis cerca. | **No sube el pánico.** Si aparece un zombi o un bandido hostil, vuelve a subir normal. |

---

# BLOQUE A — primera vuelta (04-08): lo que recogen es de verdad

Esto rompía las pruebas 2, 7 y 10 al mismo tiempo.

## Qué encontré

**Una mochila no tiene `BodyLocation`.** Yo usaba `item:getBodyLocation() == "Back"` para
reconocer un bolso. Ese campo es de **ropa**. Un bolso es un `InventoryContainer` y se declara
con `CanBeEquipped = base:back` (`container.txt:57`) — no tiene `BodyLocation` en absoluto.

Un método equivocado, cuatro síntomas tuyos:

- no recogía la mochila del suelo,
- la meta "buscar mochila" nunca se podía cumplir — **las 28 búsquedas del log dicen
  `for bag`**, ninguna la encontró,
- la mochila que sí sacó de un cajón salió como relleno, no como el objetivo,
- y por eso nunca se la equipó.

La prueba es negativa y total: 1.422 líneas `SREL` y **cero** `found what it wanted`.

**Y lo que recogen no era real.** Bandits guarda las pertenencias en el `brain`, no en
`zombie:getInventory()`. Su propio comentario lo dice (`Bandit.lua:710`): *"This translates
weapons, loot, inventory to actual items to be spawned at bandit death"*. Nunca llamábamos a
esa función, así que la lista de lo que suelta al morir seguía congelada en la del spawn —
exactamente lo que viste al matarlo. El log lo muestra sin necesidad de matar a nadie: Daniel
Green subió de `carrying 1.5` a `5.6`, y **reapareció con 1.5** conservando el nombre. El
cerebro sobrevivió al despawn; el inventario no.

**Y loteaba desde el mismo punto** porque la caminata apuntaba al mueble. Nadie puede pararse
adentro de un ropero, así que el movimiento no llegaba y la acción corría desde donde estuviera.

## Qué toqué

- El test de "esto es un bolso" ahora es el del propio motor (`ISInventoryPane.lua:967`).
- Después de saquear: se marca lo tomado, se anota en `brain.scenesCarry` y se reconstruye la
  lista de muerte con `Bandit.UpdateItemsToSpawnAtDeath`.
- `Loot.Restore` devuelve lo perdido si un despawn le vació el inventario.
- Un bolso encontrado en un cajón ahora se **pone**, igual que uno del suelo.
- Se camina a la casilla libre de al lado del mueble (`AdjacentFreeTileFinder`, lo mismo que
  usa vanilla para generadores y BBQ).

## Cómo lo probás

| # | Qué hacer | Pasa si |
|---|---|---|
| **A0** | Arrancá el juego y buscá `ASSERT` en `console.txt`. **Antes que nada.** | Sale `ASSERT ---- 10 ok, 0 FAILED ----`. Si algo dice `FAIL`, pará: el motor no tiene la forma que el código cree y el resto de las pruebas no significa nada. |
| **A1** | Entrá a una casa con un compañero y miralo lotear. | **Camina hasta cada mueble** y lo abre parado al lado. No lotea a distancia. |
| **A2** | Tirá una mochila al piso cerca de él. | La levanta y **se la pone** (se ve en el modelo). Log: `LOOT ... now carries a ...` |
| **A3** | Poné una mochila en un cajón de una casa. | Igual que A2. Log: `LOOT ... \| BAG Base.Bag_...` |
| **A4** | Con mochila puesta, dejalo lotear la casa entera. | Sigue abriendo muebles más allá de los 5–6 de antes. |
| **A5** | Dejalo saquear, alejate hasta que desaparezca, volvé. **Matalo.** | Suelta lo que recogió, no sólo el bate del spawn. |
| **A6** | Si deja de lotear, mirá el log. | Sale `COMP ... stops searching -- full` o `-- nothing left within reach`. Ahora dice **por qué**. |

---

# BLOQUE B — siguiente: seguir y huir con matemática de grupo

Todavía **no está hecho**. Queda escrito acá para no perderlo.

Tu descripción, que es la especificación:

> *"quiere volver a mi porque me está siguiendo, pero ve los zombies y luego huye. Se queda
> en ese estado de correr y volver, correr y volver."*

Y la regla que pediste:

- **3 o más zombies sobre un solo NPC (o sobre vos solo)** → reposicionarse, no quedarse
  quieto: hacer distancia y pelear desde ahí.
- **2 o más de los nuestros contra 3 zombies** → nadie se mueve, se pelea.
- Grupo chico (2–3): el que no llega **espera y llama**, no oscila. Llamar hace ruido y atrae
  más zombies — es un costo real, no gratis.
- Grupo grande (4+) con horda encima: huyen todos.

Lo que falta es el conteo de gente **nuestra** cerca; hoy la escalera sólo cuenta zombies.

---

# BLOQUE C — postergado, con razón

| Qué | Por qué espera |
|---|---|
| No se cura solo | Necesita vendas en el inventario. Sin el bloque A no hay con qué probarlo. |
| Ventana disputada, leer | Vos mismo los bajaste de prioridad. |
| ¿Descansan de verdad? | A medias. La resistencia sólo baja en Bandits; nuestro descanso es la única fuente. Se mide después del bloque A. |
| Los sueltos siguen en idle | Hay que agrandarles el radio sin que barran el mapa. Diseño en `03-autonomy.md`. |
| No aparece compañero al revivir | **El log dice que sí se pide**: 3 respawns, 3 × `TLOU\| companion requested`. Ningún NPC aparece después. El fallo está **adentro de `BanditServer.Spawner.Clan`**, no en nuestro handler. Investigación aparte. |

---

## Recordá antes de probar

- `git pull` en la PC de juego. La corrida anterior se probó con código viejo.
- Personaje **nuevo** si vas a mirar el compañero inicial.
- El kit de prueba (mochila + pistola + munición) sigue puesto y es **temporal**.
- Mandame `console.txt` y una línea por prueba, de la A1 a la A6.

---

## En qué estamos

| Etapa | Estado |
|---|---|
| [00 — Mundo de pruebas](plans/00-test-world.md) | construida, confirmada a medias |
| [01 — Memoria durable](plans/01-durable-memory.md) | **confirmada** |
| [02 — Rueda de interacción](plans/02-interaction-wheel.md) | **confirmada** |
| [03 — Autonomía](plans/03-autonomy.md) | bloque A abierto; B y C sin empezar |
| [Heridas y curación](plans/wounds-and-healing.md) | etapa 1 construida; conversión **apagada** a propósito |

En [`docs/TODO.md`](TODO.md): los cadáveres no retienen a la horda, `ClimbFence` está
comentado en Bandits, y la conversión de NPC espera al modelo de heridas.
