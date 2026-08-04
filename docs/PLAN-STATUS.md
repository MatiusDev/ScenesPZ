# Qué probar ahora

Una sola página. Se reescribe cada vez que una etapa abre o cierra. Si esta página y
cualquier otra se contradicen, ésta es la que está vieja — arreglala.

> **Nota de idioma.** Este archivo va en español porque es el que vos usás mientras jugás.
> Todo el resto — código, comentarios, planes, commits — sigue en inglés.

Hoja de ruta completa: [`docs/plans/README.md`](plans/README.md).

---

## Lo que cambió

**El escudo quedó bien** — confirmado por vos. `setNoDamage` + `setImmortalTutorialZombie`
sobre el NPC: sin daño, sin reacción de golpe. Y lo de los sombreros: empujar sigue
tumbándolos porque el empujón no es daño y no tiene veto en Lua. Misma forma que el
problema anterior, misma respuesta — ahora los vuelvo a vestir desde `brain.clothing` cada
tick lento mientras estés cerca. La sangre es una calcomanía del motor; esa no la puedo
quitar, solo la ropa vuelve a su sitio.

**El sidebar se fue al borde inferior**, y en fila en vez de en columna. Cualquier
porcentaje de la altura era una adivinanza: esa columna crece hacia abajo y hasta dónde
llega depende de qué tengas en la mano. El borde de abajo no es una adivinanza.

**La rueda:**

- **El desbordamiento era aritmética mía.** Las tarjetas llegan a `RADIUS + CARD_W/2` del
  centro y yo dimensionaba el panel con `CARD_H`. Por eso *"What are you like?"* se salía
  por la izquierda en `caps/circle-menu-2.png`.
- **Fuera el recuadro oscuro.** No enmarcaba nada y encima recortaba. Las tarjetas ya tienen
  su propio contraste.
- **El nombre y el "back" ya no se pisan.** Antes los dibujaba en el mismo punto, encima de
  las tarjetas. Ahora el centro es un recuadro propio con el nombre arriba y `back` debajo,
  y **se ilumina** cuando el cursor está en él.
- **El hover ahora es inequívoco**: relleno verde y borde doble. Era lo que pediste y
  además es lo que hace que "¿cuál voy a elegir?" se responda antes de confirmar.
- **El clic exige presionar y soltar sobre la misma tarjeta.** Actuar solo al soltar hacía
  que un clic empezado en otro lado — o un botón ya presionado cuando la rueda aparece —
  confirmara lo que hubiera bajo el cursor. Eso es lo que describiste.

---

## Lo grande: la etapa 03 cambió de sentido

Lo que dijiste es lo más útil que se ha dicho sobre este mod:

> *"no ordenan bien su cola de actividades y no las priorizan, algunos hasta se buguean
> abriendo una ventana y se quedan abriéndola, y terminan siendo mordidos por la espalda"*

Tenés razón y replantea el problema entero. **Bandits ya tiene las conductas** — 49 acciones
y 8 programas; ya lootean, trepan, abren ventanas, se refugian y pelean. Lo que no tienen es
alguien que decida **cuál importa ahora**. El síntoma no es una función que falta: es un NPC
peleando con el pestillo mientras algo se lo come.

Así que la etapa 03 ya no es "más cosas que hacer". Es la escalera que elige:

| Escalón | Se activa cuando | Hace |
|---|---|---|
| 1. Sobrevivir | acorralado, malherido, o el miedo pasa su límite | romper el cerco, meterse tras una puerta, quedarse |
| 2. Pelear | hay amenaza cerca y no le tiene tanto miedo | pelear — y **parar** cuando se resolvió |
| 3. Obedecer | le diste una orden y la aceptó | seguirte, esperar, venir |
| 4. Recado | quiere algo concreto — una venda, su mochila | ir por ello, y soltarlo si algo sube de escalón |
| 5. Ocio | nada más | el sombrero, la mochila, el armario |

**Vaciar la cola es el mecanismo entero.** `Bandit.ClearTasks` ya existe y Bandits la usa
cuando un NPC se convierte. Sin esa llamada, una intención nueva simplemente hace fila
detrás de la vieja — que es exactamente tu bug de la ventana.

Y el miedo es lo que mueve a alguien entre escalones. Eso es "las emociones deben servir en
las decisiones", hecho mecanismo en vez de adorno.

**El rango de 8 se queda por ahora**, como dijiste: sube cuando el escalón 2 ceda de verdad
ante el 1 y el 3. Ampliarlo hoy solo los hace perseguir más lejos.

El diseño completo está en `docs/plans/03-autonomy.md`, con qué produce cada escalón y cómo
se prueba. **No lo construí en esta pasada** — es la pieza más grande hasta ahora y prefiero
que primero confirmes que la rueda y el sidebar quedaron bien, porque son lo que usás para
probar todo lo demás.

---

## Antes de empezar

```bash
tools/sync-mods.sh
```

---

## Las pruebas, en orden

### 1. El sidebar ya no estorba

**Pasa si** los botones **SAFE** y **WHO** están en fila en la esquina inferior izquierda,
sin tocar la columna de íconos de vanilla. Se arrastran.

---

### 2. La rueda entra en su sitio

**Hacé:** mantené **V** cerca de alguien.

**Pasa si:**
- **Ninguna tarjeta se sale.** Comparalo con `caps/circle-menu-2.png`.
- Ya no hay recuadro gris de fondo.
- El nombre está en el centro, dentro de su propio recuadro, **sin texto encima**.

---

### 3. El hover se ve, y nada pasa solo

**Hacé:** movete sobre las tarjetas sin soltar ni hacer clic.

**Pasa si:**
- La tarjeta bajo el cursor se pone **verde con borde doble**. El centro se ilumina en
  ámbar cuando estás en un submenú.
- **No pasa nada** hasta que soltás **V** o hacés un clic completo.
- Un clic que empieza en una tarjeta y termina en otra **no** ejecuta nada.

---

### 4. Ropa y empujones

**Hacé:** con **SAFE** verde, empujá a un aliado con sombrero varias veces.

**Pasa si** el sombrero vuelve a su cabeza en menos de un minuto de juego. La sangre va a
seguir apareciendo — es una calcomanía del motor sin gancho en Lua, y no le hace nada.

---

### 5. ¿El motor mueve las emociones? — sigue pendiente

Buscá una de estas dos, sale sola:

```
PROBE stat VERDICT MOVES    PROBE stat VERDICT FROZEN
```

Esa línea decide cómo se construye el miedo de la etapa 03, así que es la que más me
sirve de esta corrida.

---

## Qué mandarme

`console.txt`, una línea por prueba, y una captura de la rueda para comparar con la
anterior.

---

## En qué estamos

| Etapa | Estado |
|---|---|
| [00 — Mundo de pruebas](plans/00-test-world.md) | construida, confirmada a medias |
| [01 — Memoria durable](plans/01-durable-memory.md) | construida, **sin confirmar** |
| [02 — Rueda de interacción](plans/02-interaction-wheel.md) | rueda arreglada (bug de closures fixed); radio reducido a 3; submenú con delay; memory test en K. **Pendiente de confirmar en juego** |

Sigue: [03 — Vida propia](plans/03-idle-life.md) — que recojan cosas, se las pongan y
looteen donde viven.
