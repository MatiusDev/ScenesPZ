# Qué probar ahora

Una sola página. Se reescribe cada vez que una etapa abre o cierra. Si esta página y
cualquier otra se contradicen, ésta es la que está vieja — arreglala.

> **Nota de idioma.** Este archivo va en español porque es el que vos usás mientras jugás.
> Todo el resto — código, comentarios, planes, commits — sigue en inglés.

Hoja de ruta completa: [`docs/plans/README.md`](plans/README.md).

---

## Lo que dijo tu log del 04-08

Cuatro respuestas, y ninguna era la que yo esperaba.

**1. El perro guardián se estaba comiendo el trabajo bueno.** Estas líneas están en tu log:

```
AUTO Benjamin Morgan | stuck on Smack@10753.5,10276.6 for 3 sweeps -- queue cleared
AUTO Benjamin Morgan | stuck on Bandage@nil,nil for 3 sweeps -- queue cleared
AUTO Benjamin Morgan | stuck on Time@nil,nil for 3 sweeps -- queue cleared
```

`Smack` es un golpe. `Bandage` es curarse. `Time` es una espera a propósito. Les estaba
cancelando las tres a mitad de camino, cada veinte segundos. Y **ni una sola vez** agarró un
`OpenWindow`, que era para lo que existía. Mi premisa estaba mal: que una tarea no cambie no
significa que esté trabada — para casi todas significa que está funcionando. Ahora sólo
vigila tareas que se completan *llegando a algún lado*, y además exige que el NPC **no se
haya movido**. Quedarse quieto sí es señal honesta.

**2. El miedo subía y nunca bajaba.** Sólo decaía cuando no había absolutamente nada cerca,
así que en una calle con zombis trepaba sin freno hasta que todos se quebraban. En tu log hay
un `fear=82/86` con **un** solo zombi al lado. Ahora es un promedio que decae: se asienta
donde la situación lo justifica y baja apenas mejora.

**3. `brain.health` no es la vida actual, es el máximo de spawn.** Se escribe una vez cuando
nace el NPC y no se toca nunca más. O sea que mi modelo de miedo leía una constante, y la
rueda tenía el mismo error: un tipo frágil te contestaba "I'm hurt. Badly." estando intacto.

**4. Y la que vos sentiste.** Encontré por qué no te siguen. No es mi código:

> `ZPCompanion.Main` — un compañero a menos de 20 tiles tuyo que ve cualquier enemigo a menos
> de 8 camina **hacia el enemigo** y sale del programa. Nunca llega al código de seguirte,
> que está al final de la misma función.

Un compañero cruzando una calle con zombis **no puede** estar siguiéndote. Es estructural. No
toqué su archivo: ahora, cuando se ve que te vas, nuestro código le impone la tarea de
seguirte y esa rama nunca llega a preguntarse nada.

---

## Qué cambió, en una tabla

| Situación | Qué hace ahora |
|---|---|
| algo a menos de 4 tiles | pelea — lo tiene encima, no hay nada que decidir |
| vos estás pegando y hay algo a menos de 8 | pelea — sumarse a tu pelea es el punto |
| vos esprintás, o la distancia crece, o pasa los 12 tiles | **te sigue**, y le imponemos la tarea |
| no tiene master | pelea dentro de 8 — no hay orden que compita |

Y dos cosas más:

- **Una persona por ventana.** Registro de reclamos por `x,y,z`. El primero que llega la
  trabaja; los demás reciben una espera real y hacen fila en vez de amontonarse.
- **El módulo de amenaza dejó de decidir.** Estaba tirando una red de 15 tiles y mandando a
  todos a la misma ventana. Ahora sólo actúa sobre quien la escalera ya puso en "sobrevivir",
  y una sola vez por episodio.

---

## Nuevo: salud del NPC

En la rueda hay una tarjeta **Health**. Abre una ventana con lo que el modelo de Bandits
realmente simula:

- **Condition** — vida viva sobre el máximo de esa persona. Verde / ámbar / rojo.
- **Infection** — el contador propio de Bandits; a 100 se convierte.
- **Weapon** — si tiene munición o no.
- Y dice en la cara que las necesidades no se simulan, en vez de dibujar barras vacías.

El botón **Bandage** te gasta una venda de verdad (alcohol primero, después normal, después
sábanas), le sube la condición y le pone la venda visible. **Vale 15 de confianza** — contra 4
de una conversación. No tiene cooldown porque no lo necesita: sólo aparece si está herido y
cada uso cuesta un ítem.

**Por qué no copié el panel del jugador:** el de vanilla es un diagrama de partes del cuerpo
alimentado por `BodyDamage`. Un NPC de Bandits no corre sobre ese modelo — su daño es un solo
número en la entidad. Dibujar el diagrama de vanilla habría sido un cuadro de ceros que
parece una función.

---

## Antes de empezar

```bash
tools/sync-mods.sh
```

---

## Las pruebas, en orden

### 1. Todo cargó

**Pasa si** están estas dos líneas nuevas:

```
SREL| AUTO ready -- survive > fight > obey > errand > idle; the player's intent outranks a distant zombie
SREL| HEALTH ready -- Health on the wheel; bandaging costs an item and moves trust
```

---

### 2. La prueba que más me sirve: salí corriendo

**Hacé:** con un compañero al lado, metete donde haya zombis y **esprintá para el otro lado
sin pelear**.

**Pasa si** te sigue corriendo en vez de quedarse peleando. En el log:

```
AUTO <nombre> | following master at 6.3 tiles (Run) -- master sprinting
```

Después alejate más de 12 tiles a propósito y mirá si te encuentra. La tarea nueva te
persigue a **vos**, no a la baldosa donde estabas, así que perderte no debería ser posible.

---

### 3. El censo — esto es lo que me falta

Cada cinco barridos ahora sale **una línea por cada NPC cerca**, incluso los que no hacen
nada. En la corrida anterior sólo tenía datos de uno de cuatro.

```
AUTO census | <nombre> | rung=obey fear=12/86 hp=0.72 z=1@6.2 friends=0 master=3.1 head=Move@10750,10280
```

**Mandame varias de éstas, de NPC distintos.** El número después del `/` es el límite de
miedo de esa persona y es suyo de por vida: uno con 30 huye mucho antes que uno con 93. Si
dos se quiebran al mismo tiempo, el modelo está mal.

---

### 4. La ventana

**Hacé:** buscá NPC cerca de ventanas con zombis alrededor.

**Pasa si** ninguno se queda pegado, y si cuando hay dos, **uno espera**. En el log:

```
AUTO <nombre> | waits, 9306146 is already working 10783,10299,0
AUTO <nombre> | stuck on OpenWindow@10864,9833 for 3 sweeps without moving -- queue cleared
```

Ojo con la segunda: si aparece con `Smack`, `Bandage` o `Time`, avisame — significa que el
filtro nuevo no alcanzó.

---

### 5. Pelear sólo cuando hace falta

**Hacé:** caminá con un compañero pasando cerca de zombis sueltos **sin atacarlos**, yendo a
algún lado concreto (un auto, una casa).

**Pasa si** te acompaña en vez de irse a cazar. Después pegale a uno vos: ahí sí debería
sumarse.

---

### 6. Salud y venda

**Hacé:** encontrá un NPC herido (o dejá que se lastime), abrí la rueda, elegí **Health**.

**Pasa si** la barra de Condition no está llena, el botón dice `Bandage` teniendo una venda
encima, y al apretarlo sube la barra. En el log:

```
HEALTH <nombre> bandaged with Base.Bandage | condition 0.90 -> 1.70 / 2.20 | neutral -> friendly
```

Si el botón dice `No bandage` teniendo vendas, avisame.

---

## Qué mandarme

`console.txt` y una línea por prueba. De la 3, **cuantas líneas `census` puedas** — es lo
único que me deja juzgar a los NPC que no hacen nada llamativo.

---

## En qué estamos

| Etapa | Estado |
|---|---|
| [00 — Mundo de pruebas](plans/00-test-world.md) | construida, confirmada a medias |
| [01 — Memoria durable](plans/01-durable-memory.md) | **confirmada en juego** |
| [02 — Rueda de interacción](plans/02-interaction-wheel.md) | **confirmada en juego** — "ya se comporta mejor" |
| [03 — Autonomía](plans/03-autonomy.md) | segunda pasada, **sin confirmar** |

Anotado y sin construir, en [`docs/TODO.md`](TODO.md): los bandidos no reaniman, los cadáveres
no retienen a la horda, y el bug de `ZPCompanion` para reportarle a Slayer.
