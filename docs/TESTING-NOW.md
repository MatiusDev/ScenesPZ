# ► Probá esto

**Esta página se REESCRIBE entera cada corrida.** No se le agrega nada. Lo que se cierra se
muda a [`docs/TEST-LOG.md`](TEST-LOG.md) y desaparece de acá.

> Español porque lo leés con el juego abierto. Todo lo demás sigue en inglés.

---

## Corrida abierta: 10-08 — follow vs fight, resistencia, rango

**Tres quejas tuyas, tres cambios.** Lo que importa ahora no son datos de diagnóstico sino
comportamiento visible. Si algo de acá falla, no es un dato — es un bug.

### Antes de arrancar

1. `git pull`.
2. En `console.txt` buscá `ASSERT ---- 30 ok, 0 FAILED ----`. Si alguna dice `FAIL`, pará y
   mandámela.
3. Apenas cargue la partida, buscá la línea de arranque que dice:
   ```
   AUTO ready -- survive > fight > obey > errand > idle | ladder <= 40 tiles, owned companions followed out to 150 | chase floor 2.5 running / 5 walking | follows lock so combat cannot steal them | walk recovery 0.01 per sweep, winded below 0.15
   ```
   Si no aparece, el archivo no cargó.

### P14 — te sigue cuando trotás (el cambio principal)

**Esto es lo que antes fallaba.** El trote (`isRunning`) era invisible. Solo detectábamos
sprint. Ahora los dos cuentan.

1. Conseguí un compañero y ponelo a pelear contra un zombie.
2. **Trotá** (no sprintees) alejándote de él.
3. **Esperado:** el compañero deja de pelear y te sigue. La línea de log dice:
   ```
   AUTO <nombre> | following master at X tiles (Run) -- combat took the last follow, re-asserting (locked)
   ```
   o
   ```
   AUTO <nombre> | following master at X tiles (Run) -- disengaging
   ```

4. Repetí la misma prueba pero **sprinteando** (lo que ya funcionaba antes). **Esperado:**
   también te sigue. Esto es regresión: si sprint funciona y trote no, avisame.

### P15 — no se queda pegado a los zombies

La causa real de "se queda pegándole a los zombies" era que `ManageCombat` borraba la tarea
de seguir y metía un golpe en su lugar. Ahora la tarea de seguir está trabada (`lock = true`)
cuando vos te estás yendo, y el combate no la puede robar.

1. Conseguí un compañero y metete en una pelea juntos contra 2-3 zombies.
2. A mitad de la pelea, **salí corriendo** (sprint o trote).
3. **Esperado:** el compañero abandona la pelea y te sigue. No se queda cambiando golpes
   mientras vos te vas.
4. El log debería mostrar una de estas dos líneas (no las dos a la vez):
   ```
   AUTO <nombre> | combat took the last follow, re-asserting (locked)
   ```
   o directamente la línea de "following master".

### P16 — te sigue aunque te alejes mucho

**Esto es lo que reportaste como "me alejé mucho y no fue capaz de regresar a mi lado".**
Antes, el compañero a más de 40 tiles simplemente dejaba de existir para el sistema. Ahora
los compañeros que te pertenecen son seguidos hasta 150 tiles por un camino barato.

1. Conseguí un compañero.
2. Alejate **más de 40 tiles** (media manzana, corriendo).
3. **Esperado:** en el censo (`AUTO census`) el compañero sigue apareciendo, con `master=X`
   donde X es la distancia real (no cortada en 40).
4. Si te alejaste de verdad (>40 tiles), buscá en el log:
   ```
   AUTO <nombre> | lost at X tiles -- outside NPC_RANGE (40), forcing follow-only
   ```
5. Cuando vuelvas a acercarte a menos de 40:
   ```
   AUTO <nombre> | found again at X tiles -- back inside 40, autonomy restored
   ```

### P17 — la resistencia no se destruye sola

**Antes `brain.endurance` solo bajaba.** Nunca se recuperaba caminando, y al llegar a cero
el NPC quedaba 16 segundos congelado en la animación de agotamiento. Ahora caminar recupera
0.01 por sweep (cada ~6 segundos), y por debajo de 0.15 el NPC prefiere descansar antes que
lootear.

1. Jugá un rato con un compañero. Movete, looteá, peleá.
2. En el censo buscá líneas que digan `winded`:
   ```
   AUTO <nombre> | winded (endurance 0.XX) -- resting preferred over looting
   ```
3. **Esperado:** no deberías ver al NPC congelado en la animación de agotamiento a cada rato.
   Si aparece, buscá en el log `Exhausted` y contame cuántas veces y en qué contexto.

### P18 — el censo dice más que antes

El censo ahora imprime más información para que podamos diagnosticar sin adivinar:

```
AUTO census | <nombre> | rung=<rung> ... head=<tarea> | was=<acción anterior> locked=<bool>
AUTO <nombre> | combat took the last follow, re-asserting (locked) -- it was Smack, now Move
AUTO <nombre> | chase started at X tiles
AUTO <nombre> | chase over -- started X, ended Y tiles
```

**No tenés que hacer nada específico para esto.** Solo jugá normal. Si ves alguna de estas
líneas, quiere decir que la telemetría nueva funciona. Si en una hora de juego no aparece
ninguna, también es un dato.

---

## Qué NO hace falta que reportes

Todo lo de [`TODO.md`](TODO.md) ya está anotado:

- el loot no entra a la mochila (el cadáver se arma con `getAllEvalRecurse`);
- juntan lapiceras y cucharas (el motor las declara `base:weapon`);
- el compañero se congela frente a una ventana estando adentro;
- el miedo cuenta zombis a través de paredes;
- un NPC cerca te levanta del sofá (verificado: no alcanzable desde Lua).

## Qué NO probar todavía

Huida y reenganche con matemática de grupo. El modelo de miedo tiene un defecto conocido
y documentado (cuenta zombis a través de paredes), y sale con el paso 5 del plan.
