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

# BLOQUE A — abierto ahora: lo que recogen es de verdad

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
