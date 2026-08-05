# Qué probar ahora

Una sola página. Se reescribe cada vez que una etapa abre o cierra. Si esta página y
cualquier otra se contradicen, ésta es la que está vieja — arreglala.

> **Nota de idioma.** Este archivo va en español porque es el que vos usás mientras jugás.
> Todo el resto — código, comentarios, planes, commits — sigue en inglés.

Hoja de ruta completa: [`docs/plans/README.md`](plans/README.md).

---

## Ya confirmado — no lo repitas

| Qué | Evidencia |
|---|---|
| Memoria durable entre descargas de celda | corrida 03-08 |
| La rueda de interacción | *"ya se comporta mejor"* |
| Saqueo acotado | `took 3`; `carrying 1.1 → 6.2 / 8.0` y parando |
| Corte con vidrios rotos | `cut on broken glass \| 1.80 -> 1.55` |
| El censo produce datos | 189 líneas `AUTO` |
| Correr detrás de un NPC que pegaba una puerta | *"si corrio detras de mi, esa parte está bien"* |

---

## Lo que arreglé de tu último reporte

**Los NPC ya no se convierten en zombi.** Tenías razón en las dos partes. Bandits no tiene
incubación: una mordida escribe un contador, le suma 0.001 por tick y a 100 los convierte.
No hay enfermedad, ni fiebre, ni deterioro — es un cronómetro. Y eso causaba el segundo bug:
al convertirse llaman `BanditRemove`, pero las cachés van un frame atrás, así que uno que ya
era zombi seguía recibiendo órdenes de volver con vos. **Dos bugs, una raíz.** Apagado con un
flag, fácil de revertir cuando el modelo de heridas pueda expresar enfermarse.

**Y por eso no te seguía.** El orden de la escalera estaba mal. Con una horda encima siempre
hay algo dentro del radio de "me tienen agarrado", así que pelear ganaba **cada barrido** y se
quedaba dando palos mientras vos te ibas. Es literal lo que describiste: *"se quedó
pegandoles"*, *"no sé si es que hubiera varios zombies cerca, no lo hizo correr"*.

Ahora **si vos corrés, él corre — por encima de todo**: del miedo, de estar agarrado, de una
calle entera. Un compañero cuyo jefe sale corriendo ya sabe cuál es el plan. Quedarse a
aguantar una horda solo no es valentía, es no haber sido avisado.

**El cansancio.** Verifiqué: sí baja y sí guarda — `BanditBrain.Get` devuelve una referencia,
no una copia. Lo que estaba mal era la aritmética. Correr cuesta 0.07 **cada vez que una
tarea de movimiento termina**, y mi tick rápido cobraba precio completo por cada corrección.
Ahora una re-asignación no cuesta nada (el viaje ya se está pagando) y descansar da el doble.

**No se curaba solo.** La decisión de vendarse vivía dentro del bloque de actividades libres,
al que un compañero sólo llega **a menos de 7 tiles tuyos**. O sea que uno herido siguiéndote
a nueve tiles nunca tenía permiso de parar. Cerrar la distancia no es más urgente que no
desangrarse.

**Y les di propósito.** Buscaban sin buscar nada: abrían lo más cercano y sacaban las primeras
tres cosas. Ahora tienen un objetivo — **mochila primero, después comida** — que decide **qué
sale primero del cajón** y aparece en el log. Lo que van a buscar ignora el tope de 3 ítems:
una mochila al fondo de un ropero no se pierde porque había latas adelante.

---

## Antes de empezar

```bash
tools/sync-mods.sh
```

**Arrancás con mochila, pistola y una caja de 9mm.** Kit de pruebas temporal para que puedas
hacer las pruebas 4, 5 y 9; está marcado para borrar en el código.

---

## Las pruebas, en orden

### 1. Correr con una horda encima

**Hacé:** juntá tres o más zombis alrededor de tu compañero y **esprintá** lejos sin pelear.

**Pasa si** sale, con **pocos** tiles:

```
AUTO <nombre> | fast follow at 6.4 tiles (Run) -- master sprinting
```

**Lo que quiero saber:** si te sigue **teniendo zombis pegados**. Antes ganaba pelear. Si
sigue quedándose, mandame las líneas `AUTO census` de ese momento — traen `rung` y la
distancia al zombi más cercano (`z=N@dist`), que es lo que decide.

---

### 2. Que busquen con propósito

**Hacé:** entrá con un compañero a una casa con muebles sin abrir y **quedate quieto**.

**Pasa si** el log dice **qué** está buscando:

```
COMP <nombre> searches 10750,10281 for bag | in=0 out=0
LOOT found what it wanted (bag): Base.Bag_Schoolbag
```

Cuando ya tenga mochila, el objetivo pasa a `food`. Si dice `for anything useful`, es que ya
tiene las dos cosas.

**Y mirá que cambie de habitación** — el límite ahora es el edificio, no el cuarto.

---

### 3. Que se cure solo

**Hacé:** dejá que baje de 0.7 de vida (miralo en el panel Health) y **no lo cures vos**.
Podés dejarlo herido y caminar: ahora puede parar a vendarse aunque esté lejos.

```
COMP <nombre> stops to dress a wound | 9.2 tiles from master
WOUND <nombre> dressed with bandage | 0.35 -> 1.71 / 1.80 | risky=false
```

`improvised` también pasa — es el piso, se rasgan la ropa.

---

### 4. Darle la mochila

**Hacé:** tirá al piso la mochila con la que arrancás, cerca de un compañero que en el censo
diga `bag=false`.

```
COMP <nombre> wants a bag -- Base.Bag_Schoolbag at 10748,10279
LOOT <nombre> now carries a Base.Bag_Schoolbag
```

Después el censo tiene que decir `bag=true`.

---

### 5. Guardar el arma adentro de una casa — pasos exactos

Esta nunca se disparó. Te la detallo porque hay que armar la situación a propósito.

1. Conseguí un NPC que **tenga un arma de fuego**. El panel **Health** te lo dice: la línea
   `Weapon` dice `loaded` si la tiene cargada, `out of ammo` si no. **Sin arma de fuego no
   hay nada que guardar y la prueba no aplica** — no la des por fallada.
2. Metelo **adentro** de una casa con vos.
3. Traé zombis **adentro**, no afuera.

**Pasa si** sale:

```
COMP <nombre> goes quiet indoors (try 1) | in=1 out=2
```

**Si ves `try 1` y `try 2` repitiéndose sin parar** para el mismo NPC, avisame: significa que
su propio combate le devuelve el arma y hay que atacarlo distinto.

---

### 6. Que uno espere en la ventana — pasos exactos

También necesita la situación armada.

1. Poné **dos** compañeros juntos.
2. Llevalos afuera, cerca de una casa **cerrada** con ventanas.
3. Traé zombis para asustar a los dos a la vez.

**Pasa si** uno reclama la ventana y el otro espera:

```
AUTO <nombre> | waits, 9306146 is already working 10783,10299,0
```

Si los dos van igual a la misma ventana, mandame las dos líneas `AUTO census` de ese momento.

---

### 7. Sentarse y cansancio

**Hacé:** caminá un rato largo, parate adentro, dejalos sentarse. **Después seguí jugando y
fijate cuánto tardan en volver a sentarse.**

```
COMP <nombre> sits down | endurance 0.42 < 0.55 | indoors
```

**Lo que quiero saber:** si el intervalo entre asientos ahora es **notablemente más largo**.
Nadie debería sentarse con `endurance 1.00`, y nadie afuera salvo por debajo de 0.25.

---

### 8. Leer

Dale un libro o un cómic a un compañero y metelo en una casa tranquila.

```
COMP <nombre> sits down with a book | endurance 0.90
```

Lo de sacar cómics de una caja que viste era el saqueo, no la lectura — son dos cosas
distintas. Puede leer **sin estar cansado**.

---

### 9. Un NPC suelto

**Hacé:** spawneá dos supervivientes, no les digas nada, y dejalos **adentro** de una casa.

**Pasa si** hacen las mismas cosas que un compañero — `searches ... for bag`, `wants a bag`.

**Sé que esto sigue flojo afuera:** un NPC suelto en la calle no tiene nada que buscar y se
queda en idle. Salir a buscar un edificio no está construido; está anotado en
`docs/plans/03-autonomy.md`.

---

### 10. Cast out y Leave me

Con un aliado de confianza alta: `Leave me` → `Follow me` tiene que **volver a aparecer**.
Después `Cast out` → la confianza queda en **0** y `Cast out` desaparece de la rueda.

---

### 11. Compañero al reaparecer

Morite, creá un personaje nuevo.

```
TLOU| new character -- one companion queued
```

Y al **recargar** un personaje que ya existe tiene que decir lo contrario, o vas a acumular
compañeros:

```
TLOU| this character already has their companion -- not spawning another
```

---

### 12. El WHO

**Muertos:** matá a alguien conocido → la fila queda, atenuada, con `dead` a la derecha.

**Por personaje:** con el personaje nuevo de la prueba 11, el WHO tiene que estar **vacío**.

```
STORE new life 412-38104 -- relationships start empty
```

---

## Qué mandarme

`console.txt` y una línea por prueba. De la 1, las `AUTO census` del momento en que corriste.

---

## En qué estamos

| Etapa | Estado |
|---|---|
| [00 — Mundo de pruebas](plans/00-test-world.md) | construida, confirmada a medias |
| [01 — Memoria durable](plans/01-durable-memory.md) | **confirmada** |
| [02 — Rueda de interacción](plans/02-interaction-wheel.md) | **confirmada** |
| [03 — Autonomía](plans/03-autonomy.md) | saqueo y vidrios confirmados; el resto sin probar |
| [Heridas y curación](plans/wounds-and-healing.md) | etapa 1 construida; conversión **apagada** a propósito |

En [`docs/TODO.md`](TODO.md): los cadáveres no retienen a la horda, `ClimbFence` está
comentado en Bandits, y la conversión de NPC espera al modelo de heridas.
