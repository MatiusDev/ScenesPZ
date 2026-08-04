# Qué probar ahora

Una sola página. Se reescribe cada vez que una etapa abre o cierra. Si esta página y
cualquier otra se contradicen, ésta es la que está vieja — arreglala.

> **Nota de idioma.** Este archivo va en español porque es el que vos usás mientras jugás.
> Todo el resto — código, comentarios, planes, commits — sigue en inglés.

Hoja de ruta completa: [`docs/plans/README.md`](plans/README.md).

---

## Lo que cambió

**El memory test pasó — la etapa 01 queda cerrada.** El almacén durable funciona: un NPC te
recuerda después de que su celda se descarga. Era la pregunta que sostenía todo el mod.

**La rueda ya no reacciona al cursor, solo al soltar.** Tenías razón en que se devolvía
antes de que eligieras: pasar el cursor por algo es lo que hacés *de camino* a otra cosa,
así que usarlo para confirmar es confirmar por accidente. Ahora:

| Soltás sobre | Pasa |
|---|---|
| una acción | se ejecuta y la rueda cierra |
| **Talk** | abre el anillo de preguntas y **la rueda sigue abierta** |
| el centro, en un submenú | vuelve al anillo principal |
| el centro, en el principal | cierra |

Después de abrir el submenú ya no estás manteniendo la tecla, así que volvé a mantener **V**
y soltá sobre la pregunta — o simplemente hacé clic. Un clic y un soltar hacen exactamente
lo mismo, es el mismo código.

El centro ahora dice *"release here to go back"*. Es una etiqueta, no un botón: no hace nada
hasta que soltás encima.

**SAFE y WHO salieron de la columna de vanilla.** No valía la pena pelear la posición:
`ISEquippedItem` arma su columna con un desplazamiento acumulado y botones que aparecen y
desaparecen según lo que tengas en la mano, si el debug está activo y si es multijugador.
Ganar esa discusión una vez no significa ganarla en el próximo parche. Ahora es un panel
propio, **y lo podés arrastrar a donde quieras**.

**El punto 7 lo resuelve la sonda sola.** Que no supieras cómo probarlo fue culpa de la
instrucción, no tuya — pedirte comparar cinco números a ojo en un log de 3 MB no era
razonable. Ahora la sonda guarda su primera lectura y escribe el veredicto sola.

---

## Etapa 03 — Vida propia, primera rebanada

**Lo que hace:** un sobreviviente ve algo en el suelo que le gustaría, camina hasta ahí, lo
recoge y **se lo pone**.

**Lo que todavía no hace:** lootear contenedores, recuperar algo que se le cayó, comerciar.
Eso es el resto de la etapa 03 y se construye cuando esta rebanada esté confirmada en una
partida real. Media etapa que funciona vale más que una entera que nunca corrió.

**El gusto es un rasgo, no un dado.** Sale de `brain.rnd`, fijo al spawn. Aproximadamente un
tercio de los sobrevivientes le presta atención a la ropa, y a cuál — sombreros, mochilas o
chaquetas — también es suyo de por vida. El que recoge todos los sombreros los recoge
**siempre**, y eso es algo que aprendés de él. Un azar por tick los volvería a todos la misma
persona comportándose de forma inconsistente, que es lo contrario del objetivo.

**La regla que más importa:** nada de esto puede interrumpir una pelea ni una orden. El
chequeo de ocio es estricto — cola de tareas vacía, ningún zombi cerca, y no está huyendo.

---

## Antes de empezar

```bash
tools/sync-mods.sh
```

---

## Las pruebas, en orden

### 1. Todo cargó y nada explota

**Hacé:** entrá, jugá dos minutos, salí y buscá `setTextureColor` en `console.txt`.

**Pasa si** no aparece. Y si están las siete líneas de arranque:

```
SREL| STORE ready    SREL| GUARD ready     SREL| SIDEBAR ready
SREL| WHEEL ready    SREL| MEMTEST ready   SREL| IDLE ready
SREL| PANEL ready
```

---

### 2. La rueda selecciona al soltar

**Hacé:** mantené **V** cerca de alguien, movete sobre una tarjeta, soltá.

**Pasa si:**
- Ya **no** se devuelve solo al pasar el cursor por el centro.
- Soltar sobre `Talk` abre las preguntas y la rueda **se queda abierta**.
- Volvé a mantener **V** (o hacé clic) y soltá sobre una pregunta: sale la respuesta.
- Soltar en el centro dentro del submenú vuelve al anillo principal.
- Soltar en el centro del anillo principal cierra.

---

### 3. Los botones ya no tapan nada

**Hacé:** mirá el borde izquierdo, a media altura.

**Pasa si** hay un panelito con **SAFE** y **WHO** que **no** se superpone con los íconos de
construcción, y podés **arrastrarlo**.

---

### 4. Vida propia — la nueva

**Hacé, en este orden:**

1. Conseguí dos o tres sobrevivientes cerca.
2. Tirá al suelo delante de ellos **un sombrero, una mochila y una chaqueta**.
3. Alejate un poco y esperá. Que no haya zombis cerca.

**Pasa si:**
- **Algunos** van, lo recogen y se lo ponen. **Otros pasan de largo.** Las dos cosas son
  correctas — solo un tercio son así.
- En el log: `IDLE <nombre> wants Base.Hat_... at x,y` y después
  `IDLE <nombre> put on Base.Hat_...`.
- **El mismo sobreviviente se comporta igual la segunda vez.** Eso es lo que prueba que es
  un rasgo y no un azar.

**Y la prueba que de verdad importa:** mientras uno va caminando hacia el objeto, **traé un
zombi**. Tiene que abandonarlo. Si sigue caminando hacia el sombrero mientras algo te está
mordiendo, eso es un fallo y hay que arreglarlo antes que nada.

---

### 5. El escudo — ahora sí, ingolpeables

Preguntaste si se podía hacer que el golpe **no exista**, en vez de curar después. Sí se
puede, y era la pregunta correcta: curar es un parche, y encima mi versión anterior ni
siquiera curaba.

El motor lo tiene, y vanilla lo llama **sobre un zombi** — que es lo que lo distingue de
todo lo que probé antes:

```lua
-- pzserver/media/lua/client/Tutorial/Steps.lua:848, 934
FightStep.momzombie:setNoDamage(true)
FightStep.momzombie:setImmortalTutorialZombie(true)
```

El tutorial las usa para volver intocable a un zombi concreto durante un momento guionado.
Por eso `setInvincible` fallaba en silencio: esa solo aparece sobre jugadores.

**Una consecuencia que tenés que saber.** `setNoDamage` es una bandera general: un NPC que
la lleva tampoco puede ser mordido por zombis. Un aliado inmordible es otro juego. Por eso
**solo se activa mientras estás a 4 tiles o menos** — cuando el accidente es posible — y se
apaga en cuanto te alejás. Tres caminos distintos la apagan, porque un aliado inmortal
permanente sería peor bug que el que arreglo.

**Hacé:** con **SAFE** verde y un aliado al lado, pegale seis o siete veces seguidas.

**Pasa si:**
- **No hay animación de golpe, no hay sangre, no baja la vida.** Nada.
- En el log: `GUARD <nombre> | trust kept, no damage to undo`.
- Alejate 10 tiles, traé un zombi y comprobá que **sí lo puede morder**. Si es inmune a los
  zombis lejos tuyo, la bandera se quedó pegada y eso es un fallo.
- Poné **HIT** (rojo) y comprobá que ahí sí le hacés daño.

**Si aparece esta línea**, la bandera no funciona sobre un bandido y volvemos a curar:

```
GUARD setNoDamage is not available on this NPC
```

---

### 6. Las emociones, ahora con veredicto automático

No tenés que comparar nada. Buscá una de estas dos líneas:

```
PROBE stat VERDICT MOVES   -- el motor sí las mueve, se pueden leer
PROBE stat VERDICT FROZEN  -- diez barridos sin cambio, hay que simularlas
```

Sale sola después de unos minutos con un NPC cerca.

---

## Qué mandarme

`console.txt` y una línea por prueba. De la 4, si alguno abandonó el objeto al llegar un
zombi. De la 5, si le bajó la vida. De la 6, cuál de las dos líneas salió.

---

## En qué estamos

| Etapa | Estado |
|---|---|
| [00 — Mundo de pruebas](plans/00-test-world.md) | construida, confirmada a medias |
| [01 — Memoria durable](plans/01-durable-memory.md) | construida, **sin confirmar** |
| [02 — Rueda de interacción](plans/02-interaction-wheel.md) | rueda arreglada (bug de closures fixed); radio reducido a 3; submenú con delay; memory test en K. **Pendiente de confirmar en juego** |

Sigue: [03 — Vida propia](plans/03-idle-life.md) — que recojan cosas, se las pongan y
looteen donde viven.
