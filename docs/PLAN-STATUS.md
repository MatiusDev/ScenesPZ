# Qué probar ahora

Una sola página. Se reescribe cada vez que una etapa abre o cierra. Si esta página y
cualquier otra se contradicen, ésta es la que está vieja — arreglala.

> **Nota de idioma.** Este archivo va en español porque es el que vos usás mientras jugás.
> Todo el resto — código, comentarios, planes, commits — sigue en inglés.

Hoja de ruta completa: [`docs/plans/README.md`](plans/README.md).

---

## Ya confirmado — no lo repitas

Esto salió bien en una corrida real y sólo vuelve a esta lista si lo rompo.

| Qué | Evidencia |
|---|---|
| Memoria durable entre descargas de celda | corrida 03-08 |
| La rueda de interacción | *"ya se comporta mejor"* |
| Saqueo acotado | `took 3` respetando el tope; `carrying 1.1 → 6.2 / 8.0` y **parando** |
| Corte con vidrios rotos | `cut on broken glass \| 1.80 -> 1.55` |
| El censo produce datos | 189 líneas `AUTO` en la corrida 04-08 16:31 |
| Los doce subsistemas cargan | doce líneas `ready` |

De ahora en más, la prueba 0 es sólo mirar que estén las líneas `ready` al arrancar. Si falta
alguna, pará y decime cuál.

---

## Lo nuevo de la etapa 03

**1. Retomar lo interrumpido.** Era el criterio de cierre de la etapa, escrito hace tres
sesiones: *"un superviviente interrumpido mientras saquea mata al zombi y vuelve al
contenedor"*. Vaciar la cola es lo que hace funcionar la escalera, y también era lo que
borraba lo que estaban haciendo. Ahora la escalera **guarda la intención** antes de vaciar, y
el compañero la retoma cuando se calma. Caduca a los ~2 minutos o si quedó a más de 15 tiles.

**2. Ahora sí se curan.** El disparador de curación de Bandits exige que la cola no tenga
nada más que movimiento — y con la escalera dándoles cosas que hacer, eso no pasa casi nunca.
En tu log está la prueba: abriste el panel de John Jones en `condition 0.02 / 1.80`, infectado,
a dos centésimas de morirse, y **no hay una sola línea `dressed with` en toda la corrida**.
Ahora la decisión de curarse es nuestra; la acción, la animación y el sonido siguen siendo de
ellos.

**3. Saquean la casa entera, no un cuarto.** Estaba limitado a la habitación donde estaban
parados — por eso ambos revisaron cuatro o seis muebles y se detuvieron. Ahora el límite es
el **edificio**. No puede irse a la casa de al lado.

Y lo del turno anterior, que aún no probaste: seguimiento rápido, la puerta del sentarse, y
leer.

---

## Antes de empezar

```bash
tools/sync-mods.sh
```

---

## Las pruebas, en orden

### 0. Arrancó todo

Mirá que estén las doce líneas `ready`. Si falta `COMP ready` o `WOUND ready`, nada de lo
nuevo está corriendo y el resto de las pruebas no significan nada.

---

### 1. Salí corriendo en medio de una pelea

**La más importante.** Con zombis al lado, esprintá para el otro lado sin pelear.

**Pasa si** sale la línea del tick rápido, y con **pocos** tiles:

```
AUTO <nombre> | fast follow at 6.4 tiles (Run) -- master sprinting
```

**Si el número pasa de 10, avisame** — significa que el tick rápido no entró.

Antes esperaba a 25.9 tiles porque un zombi a 4 le ganaba a que vos corrieras. Ahora sólo uno
a **1.6 tiles** lo clava en el lugar.

---

### 2. Que vuelva a lo que estaba haciendo

**Hacé:** metelo en una casa a saquear, y cuando esté abriendo un mueble, traele un zombi.

**Pasa si** salen las dos líneas, en este orden:

```
AUTO <nombre> | sets aside search at 10750,10281
COMP <nombre> goes back to the search at 10750,10281
```

La primera es la escalera guardando la intención antes de vaciar la cola. La segunda es él
volviendo. **Si sale la primera y nunca la segunda, decime** — se está perdiendo en el camino
de vuelta.

---

### 3. Que se cure solo

**Hacé:** dejá que un compañero baje de 0.7 de vida (el panel de salud te lo dice) y no lo
vendes vos. Esperá.

**Pasa si** sale:

```
COMP <nombre> stops to dress a wound
WOUND <nombre> dressed with bandage | 0.35 -> 1.71 / 1.80 | risky=false
```

`improvised` en vez de `bandage` también pasa — es el piso, se rasgan la ropa. Lo que **no**
puede pasar es que llegue a 0.02 como John Jones y no salga ninguna de las dos.

---

### 4. La casa entera

**Hacé:** entrá a una casa de varias habitaciones y quedate quieto.

**Pasa si** las coordenadas de las líneas `searches` **cambian de habitación** — antes se
quedaba en una sola.

```
COMP <nombre> searches 10750,10281 | in=0 out=0
COMP <nombre> searches 10758,10275 | in=0 out=0
```

Y que **no cruce la calle**. Si lo ves entrar a la casa de al lado, es un bug.

---

### 5. Sentarse

**Hacé:** caminá un rato largo para gastarles energía, después parate adentro de una casa.

**Pasa si** el número de la izquierda es **siempre menor** que el de la derecha:

```
COMP <nombre> sits down | endurance 0.42 < 0.55 | indoors
COMP <nombre> sits down | endurance 0.71 < 0.80 | indoors, the lazy sort
```

**Nadie con `endurance 1.00`, y nadie afuera salvo por debajo de 0.25.** Antes eran 21 de 38
asientos a energía llena.

Y mirá el orden: un perezoso en una casa con muebles sin abrir **saquea primero**. Si se
sienta teniendo cajones sin tocar, decime.

---

### 6. Leer

Un cuarto de ellos lee. Dale un libro a un compañero y metelo en una casa tranquila.

```
COMP <nombre> sits down with a book | endurance 0.90
```

Puede leer **sin estar cansado** — es lo único que hacen porque quieren.

---

### 7. La mochila

Antes el censo decía `bag=?` para todos por un bug mío, así que esto nunca se pudo ver.

**Hacé:** tirá una mochila cerca de un compañero que el censo marque `bag=false`.

```
COMP <nombre> wants a bag -- Base.Bag_Schoolbag at 10748,10279
LOOT <nombre> now carries a Base.Bag_Schoolbag
```

Después `bag=true` y su `carrying` máximo sube.

---

### 8. Las dos que nunca se dispararon

Estas dos no aparecieron ni una vez en tu corrida. No sé si funcionan o si nunca se dio la
situación.

**Guardar el arma adentro de una casa** — pelealo adentro con un arma de fuego encima:

```
COMP <nombre> goes quiet indoors (try 1) | in=1 out=2
```

**Uno espera a que el otro pase la ventana** — necesitás dos NPC yendo a la misma ventana:

```
AUTO <nombre> | waits, 9306146 is already working 10783,10299,0
```

Si con la situación armada no salen, decímelo y las miro con otro enfoque.

---

### 9. Un NPC suelto ya no se queda mirando la pared

Todo lo que construimos vivía dentro del envoltorio de compañero, así que la única forma de
tener vida interior era estar siguiéndote. Ahora la cadena de actividades es compartida y
también envuelve `Looter`.

**Hacé:** spawneá un NPC nuevo, no le digas nada, y dejalo dentro de una casa.

**Pasa si** hace cosas por su cuenta — las mismas líneas `COMP ... searches`, `wants a bag`,
`sits down`, pero de alguien que no es tu compañero.

En el arranque, la línea de `COMP ready` ahora dice cuál de los dos programas envolvió:

```
COMP ready -- wraps ZPCompanion.Main and ZPLooter.Main: ...
```

Si dice `ONLY (no Looter to wrap)`, avisame.

---

### 10. El radio según el vínculo

| Vínculo | Radio | Se debería ver como |
|---|---|---|
| sin grupo | 10 | el más lanzado, va por lo que ve |
| te sigue | 8 | como estaba |
| en el clan (join) | **6** | **defiende**, no caza |

**Pasa si** un aliado del clan se queda más pegado a vos que uno que sólo te sigue, con los
mismos zombis alrededor. Es sutil — mirá el `census`, que trae `rung` y la distancia al
zombi más cercano (`z=N@dist`).

---

### 11. Leave me y Cast out

**Leave me** ya no es una expulsión. Adentro de un edificio los pasa a `Defend` (se quedan
cuidando el lugar), afuera a `Looter`. **La confianza no se toca.**

```
ACT <nombre> | leave -> Defend | trust=80 ...
```

**Cast out** es la expulsión, y sólo aparece si ya hizo *Join me*. Le pone la confianza en
**0** de un golpe.

```
ACT <nombre> | cast out | trust=0 ...
```

Comprobá las dos cosas: que `Cast out` **no** aparezca en alguien que sólo te sigue, y que
después de usarlo el WHO lo muestre en 0.

---

### 12. El WHO

Dos bugs que reportaste.

**Los muertos.** Matá o dejá morir a alguien con quien tengas relación y abrí el WHO.

**Pasa si** la fila sigue estando, atenuada, y dice `dead` a la derecha. El registro se queda
a propósito — uno no deja de haber conocido a alguien porque se murió — pero antes un aliado
muerto y uno vivo se veían igual.

```
STORE <nombre> died | trust 80 at the end
```

**Las relaciones son por personaje.** Morite y volvé a entrar con uno nuevo.

**Pasa si** el WHO aparece **vacío**. En el log:

```
STORE new life 412-38104 -- relationships start empty
```

Y si te cruzás con alguien que conocía tu personaje anterior, te trata como a un desconocido:

```
STORE 9306146 belonged to a previous life -- starting over
```

> Las relaciones de partidas viejas, de antes de este arreglo, **se conservan** — no tienen
> marca de vida y se adoptan. Sólo empieza a separar desde acá.

---

## Qué mandarme

`console.txt` y una línea por prueba. De las líneas `AUTO census`, cuantas puedas — es lo
único que me deja juzgar a los NPC que no hacen nada llamativo.

---

## En qué estamos

| Etapa | Estado |
|---|---|
| [00 — Mundo de pruebas](plans/00-test-world.md) | construida, confirmada a medias |
| [01 — Memoria durable](plans/01-durable-memory.md) | **confirmada** |
| [02 — Rueda de interacción](plans/02-interaction-wheel.md) | **confirmada** |
| [03 — Autonomía](plans/03-autonomy.md) | saqueo y vidrios confirmados; retomar, curarse y casa entera **sin probar** |
| [Heridas y curación](plans/wounds-and-healing.md) | etapa 1 construida; 2 y 3 diseñadas |

Anotado y sin construir, en [`docs/TODO.md`](TODO.md): los bandidos no reaniman, los cadáveres
no retienen a la horda, y `ClimbFence` está comentado en Bandits — por eso se traban en las
vallas.
