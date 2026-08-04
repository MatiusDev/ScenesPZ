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

## Nuevo: pisamos ZPCompanion (sin reemplazarlo)

Capturo `ZombiePrograms.Companion.Main` y la guardo. Nuestra función decide **sólo** los
casos donde tenemos opinión y le devuelve todo lo demás a la de ellos, intacta. Su combate,
sus armas, sus guardposts y su código de seguirte siguen corriendo — y siguen arreglándose
cuando Slayer los arregle.

**Y encontré por qué nunca lootean.** No es configuración:

> `BanditPrograms.Container.Loot` es **código muerto**. La línea 524 lee
> `enemyCharacter:getX()` y la 541 lee `endurance`, y ninguno de los dos es parámetro ni
> local de esa función. Son globales indefinidos: la primera llamada revienta.

Por eso todo el bloque de looting en `ZPCompanion.Main` (líneas 120-215) está comentado. No
está desactivado esperando ajustes — está desactivado porque crashea. **Nadie ha visto nunca
a un compañero de Bandits saquear una casa.** Hubo que escribirlo.

### Lo que hacen ahora dentro de una casa

| Situación | Actividad |
|---|---|
| adentro, nada adentro con ellos, nadie golpeando | **saquean** |
| algo ya adentro, o **2+** golpeando afuera | **despejan la zona primero** |
| adentro y peleando | **cambian a cuerpo a cuerpo** — matar en silencio |
| **4+** ya adentro | el miedo los sube a sobrevivir → se van |

Saquean **acotado**: máximo 3 ítems por contenedor y hasta el 70% de su capacidad. Los dos
límites son a propósito — el de ítems para que **no te vacíen la casa antes de que llegues**,
y el de peso para que no se saturen.

**Sin mochila, buscan mochila primero.** `brain.bag` se asigna al spawn y nunca hubo forma de
conseguir una; el que nació sin ella se llenaba en tres ítems. Ahora una mochila en el suelo
vale más que cualquier cosa que pudiera cargar.

### Y lo de sentarse

Tenías razón en el diagnóstico pero la causa era otra: no te estaban copiando. Cuando parás,
su `Main` cae a `BanditPrograms.Idle`, que es una bolsa de animaciones nerviosas —
`ChewNails`, `Sneeze`, `WipeBrow`. Parecían esperando el colectivo.

Ahora **no copian que te sientes**. Se sientan si:

- **están realmente cansados** (`brain.endurance < 0.55`), o
- **son de los que se sientan** — uno de cada cinco, fijo de por vida (`brain.rnd[4]`)

Si no, **miran hacia donde vendría el problema**.

> Detalle que encontré: `brain.endurance` **sólo baja**. `Bandit.UpdateEndurance` se llama
> desde un solo lugar y todos los programas pasan 0 o negativo — nada en Bandits la
> devuelve nunca. Así que sentarse ahora la **restaura**, usando el mismo campo
> `task.endurance` que ellos ya aplican. Es lo único en todo el framework que da energía.

---

## Antes de empezar

```bash
tools/sync-mods.sh
```

---

## Las pruebas, en orden

### 1. Todo cargó

**Pasa si** están estas cuatro líneas nuevas:

```
SREL| AUTO ready -- survive > fight > obey > errand > idle; the player's intent outranks a distant zombie
SREL| HEALTH ready -- Health on the wheel; bandaging costs an item and moves trust
SREL| LOOT ready -- bounded searching; upstream Container.Loot is dead code and unused
SREL| COMP ready -- wraps ZPCompanion.Main: search, bags, quiet indoors, real rest
```

La cuarta es la crítica. Si falta, aparecerá en su lugar
`COMP could not install -- ZombiePrograms.Companion.Main is not there`, y significa que el
orden de carga de mods cambió y nada de lo nuevo corre.

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

### 7. Saqueo — la prueba nueva más importante

**Hacé:** entrá en sigilo a una casa **limpia**, con un compañero, y quedate quieto un rato.

**Pasa si** se pone a abrir muebles solo. En el log:

```
COMP <nombre> searches 10750,10281 | in=0 out=0
LOOT <nombre> took 3 from 10750,10281 | carrying 4.2 / 8.0
```

**Mirá dos cosas concretas:**

- Que **no te vacíe la casa**: `took 3` es el techo por contenedor. Si ves `took` con más
  de 3, el límite no está funcionando.
- Que `carrying` **pare** antes del máximo. Si llega al tope y sigue, avisame.

---

### 8. Despejar antes de saquear

**Hacé:** lo mismo pero con zombis golpeando la puerta.

**Pasa si** dejan de saquear y van a matar. En el log el rung cambia a `fight` y el censo
muestra los números que lo decidieron:

```
AUTO census | <nombre> | rung=fight ... in=0 out=3 indoors ...
```

Y adentro deberían **guardar el arma de fuego**:

```
COMP <nombre> goes quiet indoors (try 1) | in=1 out=2
```

Si ves `try 1` y `try 2` repetidos sin parar para el mismo NPC, avisame — significa que su
combate le está devolviendo el arma y hay que atacarlo distinto.

---

### 9. La mochila

**Hacé:** tirá una mochila al piso cerca de un compañero **que no tenga una** (mirá el censo:
`bag=false`).

**Pasa si** va a buscarla y se la pone:

```
COMP <nombre> wants a bag -- Base.Bag_Schoolbag at 10748,10279
LOOT <nombre> now carries a Base.Bag_Schoolbag
```

Después el censo debería decir `bag=true` y su `carrying` máximo debería subir.

---

### 10. Sentarse

**Hacé:** sentate vos en una casa despejada con dos compañeros al lado.

**Pasa si** ellos **no** se sientan sólo porque vos lo hiciste. Uno de cada cinco se sienta
por su cuenta, y cualquiera que haya corrido mucho también:

```
COMP <nombre> sits down (tired) | endurance 0.41
COMP <nombre> sits down (just the sort) | endurance 0.88
```

Los demás deberían quedarse mirando hacia el peligro más cercano, no haciendo tics
nerviosos. **Y si algo se les acerca a 4 tiles, se levantan y se defienden.**

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
