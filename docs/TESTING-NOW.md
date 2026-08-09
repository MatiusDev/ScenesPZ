# ► Probá esto

**Esta página se REESCRIBE entera cada corrida.** No se le agrega nada. Lo que se cierra se
muda a [`docs/TEST-LOG.md`](TEST-LOG.md) y desaparece de acá.

> **Nota de idioma.** Este archivo va en español porque es el que usás mientras jugás.
> Todo el resto — código, comentarios, planes, commits — sigue en inglés.

---

## Corrida abierta: 09-08 (segunda vuelta) — los tres que fallaron

**B1 y B3 ya pasaron y no hace falta repetirlos.** El kit está bien y la capacidad de la mochila
funciona: *"ya veo que funciona mucho mejor la capacidad de looteo"*.

Esta corrida es **solo los tres que fallaron**, y de los tres, dos fallaron por errores míos que
el log nombró con todas las letras.

### Antes de arrancar

1. `git pull` en la PC de juego.
2. Personaje **nuevo** para B2 y A7.

### Primero, siempre

`ASSERT ---- 25 ok, 0 FAILED ----` en `console.txt`. Si algo dice `FAIL`, pará y mandámelo.

### Las pruebas

| # | Qué hacer | Pasa si |
|---|---|---|
| **B2** | Dale una mochila a un NPC y quedate mirándolo. | **Se le ve puesta.** Y ahora el log te dice qué pasó aunque falle: `LOOT ... wears the ...` si funcionó, o `LOOT ... cannot wear it -- <razón>` si no. **Mandame esa línea en cualquiera de los dos casos.** |
| **B2b** | Matalo después de que se la puso. | La mochila queda en el cadáver **una sola vez**, no dos. Esto pasaba antes y lo toqué, hay que confirmarlo de nuevo. |
| **B4** | Parate pegado a tus compañeros, sin zombis cerca. | **El pánico no sube.** Si sube, buscá `PANIC handler threw` en el log — ahora sale una sola vez y dice la causa. |
| **A7** | Tirá **cualquier prenda** al piso cerca de un NPC libre y esperá 2–3 minutos de juego, **sin zombis a la vista**. | Camina, la levanta y se la pone. Log: `IDLE ... wants ...`. Si no sale ni una línea `IDLE`, mandámelo. |

### Qué NO hace falta que mires

Ya pasó: el kit de prueba (B1), la capacidad de la mochila (B3), y todo el bloque A.

### Qué ya sé que sigue roto

Están **todos anotados en `TODO.md`**, no hace falta que los reportes de nuevo:

- se quedan peleando en vez de seguirte cuando huís;
- lootean cerca pero no lo suficiente para saber qué mueble abren;
- **los golpes cuerpo a cuerpo se enfocan en el NPC amigo** aunque no le hagan daño;
- la resistencia se agota demasiado rápido y sin etapas;
- los muertos desaparecen en vez de quedarse y convertirse;
- se traban contra puertas y ventanas.

---

## Qué cambió, y por qué falló antes

**B4 — el pánico.** El log lo dijo textual: `PANIC handler threw: Object tried to call nil in
onlyFriendsNear`. Copié `getSeeNearbyCharacterDistance()` del handler de Slayer sin verificarlo,
y ese método tiene **cero callsites en los 2.680 archivos del motor** — solo existe dentro del
código que él dejó apagado, que es probablemente por qué lo apagó. Rompí mi propia regla:
*el código vendorizado no es fuente de verificación*. Ahora es una constante nuestra, y hay una
aserción que la cubre.

Segundo error en el mismo archivo, que habría sobrevivido al primer arreglo: corría cada **diez**
minutos de juego, casi un minuto real. El pánico sube todo el tiempo, así que entre dos barridos
recorría tranquilo → Nervioso → Alarmado, exactamente como lo viste. Ahora corre cada minuto.

**B2 — la mochila.** Falló **en silencio**, que es lo peor: no tiró excepción, no logueó nada.
Instanciaba una mochila nueva que no estaba en ningún inventario y trataba de vestirla — y
`WearBag` sacaba la real del inventario diez líneas antes. En vanilla siempre se viste algo que
el personaje ya tiene. Ahora se agrega al inventario y se viste **esa**, y el log dice cuál de
los pasos falló si falla.

**A7 — no estaba roto, estaba invisible.** Un tercio de los NPC tenía interés en ropa, y ese
tercio se fijaba en **una sola** de tres categorías: la chance de que un NPC dado quisiera la
prenda que tiraste era ~1 de 9. Con dos NPC no lo ibas a ver nunca. En 1,7 MB de log había
exactamente una línea `IDLE`: el banner de arranque. Ahora dos tercios se interesan y les sirve
cualquier prenda. Además el radio de "hay zombis, no es momento" bajó de 12 a 8 tiles — 12 es
media cuadra, y en Knox casi siempre hay algo dentro de 12, así que la conducta estaba cerrada
con llave casi todo el tiempo.
