# Qué probar ahora

Una sola página. Se reescribe cada vez que una etapa abre o cierra. Si esta página y
cualquier otra se contradicen, ésta es la que está vieja — arreglala.

> **Nota de idioma.** Este archivo va en español porque es el que vos usás mientras jugás.
> Todo el resto — código, comentarios, planes, commits — sigue en inglés.

Hoja de ruta completa: [`docs/plans/README.md`](plans/README.md).

---

## Etapa 03 — construida la base

**Confirmé tu diagnóstico y era más exacto de lo que creías.** `ZPCompanion` **ya replica
todo**: cambia a correr si esprintás, a agachado si te agachás, a apuntar si apuntás, a
cojear si está herido — todo en `ZPCompanion.lua:38-56`. Esa conducta no falta.

Lo que pasa es una línea del diseño de Bandits: **un programa solo corre cuando la cola de
tareas está vacía.** Un NPC tres tareas metido en abrir una ventana nunca llega al código
que habría notado que corrés, ni al que habría notado al zombi detrás. No te ignora. Nunca
le preguntan.

Así que no agregué ni un verbo. Agregué quién decide.

### La escalera

| Escalón | Se activa cuando |
|---|---|
| 1 sobrevivir | acorralado, malherido, o con más miedo del que aguanta |
| 2 pelear | hay amenaza cerca y no le tiene tanto miedo |
| 3 obedecer | aceptó una orden y tiene master |
| 4 recado | quiere algo concreto y va por ello |
| 5 ocio | nada más |

**Subir de escalón vacía la cola** con `Bandit.ClearTasks` — que ya existe, que Bandits usa
cuando un NPC se convierte, y que respeta las tareas marcadas `lock`. Bajar **no** la vacía:
terminar lo que empezaste es correcto, y vaciar en cada cambio sería un NPC que nunca
completa nada.

### El miedo elige el escalón

`brain.rnd[2]` está fijo al spawn — el mismo campo que ya usaba el módulo de amenaza para la
valentía, a propósito, para que los dos nunca discrepen sobre quién es valiente. **Un
cobarde se quiebra en 30; uno templado aguanta hasta 93.** El miedo sube con zombis cerca,
con estar en inferioridad y con estar herido; baja solo cuando nada de eso pasa.

### Y el perro guardián

Si un NPC lleva tres barridos con la misma tarea en la cabeza de la cola, se le vacía. Es el
arreglo directo de tu bug de la ventana, y vale la pena tenerlo por buena que quede la
escalera, porque atrapa cualquier variante futura de "atascado" sin saber qué la causó.

**El ocio pasó a ser el escalón 5.** Ya no decide por su cuenta si está libre: le pregunta a
la escalera.

---

## Anotado en `docs/TODO.md`, sin construir

- **Los bandidos no reaniman.** Bandits tiene la maquinaria (`ZAZombify`, y encolan
  `Zombify` cuando `brain.infection >= 100`), pero va por su modelo de infección, no por el
  temporizador de vanilla. La pregunta a responder primero: ¿un NPC muerto de golpe llega a
  acumular infección, o solo sube al sobrevivir una mordida?
- **Los cadáveres no retienen a la horda.** Y tenés razón en por qué importa: sacrificar a
  alguien debería *comprar* algo, y hoy no compra nada. `brain.eatBody` existe, lo cual
  sugiere que el estado de comer un cuerpo ya está modelado — hay que leerlo antes de
  diseñar nada.

También encontré que **`docs/NEXT-STEPS.md` estaba obsoleto y mentía** — decía que
ScenesRelations nunca se había corrido, y sostenía la afirmación ya retractada de que el id
identifica un atuendo. Lo dejé como redirect para que no sea una trampa.

---

## Antes de empezar

```bash
tools/sync-mods.sh
```

---

## Las pruebas, en orden

### 1. Todo cargó

**Pasa si** está la línea nueva junto a las demás:

```
SREL| AUTO ready -- survive > fight > obey > errand > idle, and fear picks the rung
```

---

### 2. El bug de la ventana

**Hacé:** encontrá NPC cerca de ventanas con zombis alrededor y observalos un rato.

**Pasa si** ninguno se queda pegado a una ventana. En el log:

```
AUTO <nombre> | stuck on OpenWindow@10864,9833 for 3 sweeps -- queue cleared
```

Esa línea es la prueba de que el perro guardián lo agarró.

---

### 3. La escalera reacciona

**Hacé:** con un compañero siguiéndote, llevalo hacia varios zombis.

**Pasa si** aparecen líneas así, con los números:

```
AUTO <nombre> | obey -> fight | fear=24/58 zombies=2 friends=1 | queue cleared
AUTO <nombre> | fight -> survive | fear=71/58 zombies=5 friends=0 | queue cleared
```

**Lo que quiero que mires:** que **dos NPC distintos no se quiebren al mismo tiempo**. El
límite después del `/` es suyo de por vida — uno con 30 huye mucho antes que uno con 93.

---

### 4. Ahora sí, ¿te replica?

Ya que la cola deja de bloquearlos: esprintá y luego agachate con un compañero al lado.

**Pasa si** ahora te sigue el ritmo. Esto no lo programé yo — es `ZPCompanion` que por fin
llega a ejecutarse.

---

### 5. La rueda — quedó de la corrida anterior

Que las tarjetas no se salgan, que el hover se vea verde, y que nada se ejecute sin soltar
o sin un clic completo.

---

### 6. ¿El motor mueve las emociones? — sigue pendiente

```
PROBE stat VERDICT MOVES    PROBE stat VERDICT FROZEN
```

Ahora importa más que antes: si dice `MOVES`, el miedo que acabo de construir puede leerse
del motor en vez de simularse.

---

## Qué mandarme

`console.txt` y una línea por prueba. De la 3, dos líneas `AUTO` de NPC distintos para
comparar sus límites de miedo.

---

## En qué estamos

| Etapa | Estado |
|---|---|
| [00 — Mundo de pruebas](plans/00-test-world.md) | construida, confirmada a medias |
| [01 — Memoria durable](plans/01-durable-memory.md) | construida, **sin confirmar** |
| [02 — Rueda de interacción](plans/02-interaction-wheel.md) | rueda arreglada (bug de closures fixed); radio reducido a 3; submenú con delay; memory test en K. **Pendiente de confirmar en juego** |

Sigue: [03 — Vida propia](plans/03-idle-life.md) — que recojan cosas, se las pongan y
looteen donde viven.
