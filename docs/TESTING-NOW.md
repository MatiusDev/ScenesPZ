# ► Probá esto

**Esta página se REESCRIBE entera cada corrida.** No se le agrega nada. Lo que se cierra se
muda a [`docs/TEST-LOG.md`](TEST-LOG.md) y desaparece de acá.

> Español porque lo leés con el juego abierto. Todo lo demás sigue en inglés.

---

## Corrida abierta: 11-08b — P19 glass timing, P24 window smash, P20 panic, P25 health UX

**Fixes del feedback de la corrida 11-08a.** Si algo de acá falla, es un bug nuevo.

### Antes de arrancar

1. `git pull`.
2. Buscá `ASSERT ---- 30 ok, 0 FAILED ----`. Si dice `FAIL`, pará.
3. Confirmá que estos módulos cargaron:
   ```
   HEALTH ready -- 17-part body display, condition bar, bandage action
   WOUND ready -- every window crossing costs blood (climb watcher every 200 ms)
   PANIC ready -- spike detector active; suppression starts on tick 1 (no game-start gap)
   PATHFINDING ready -- preemptive route check before move
   ```

---

### P19 — WOUND: daño de vidrio solo al cruzar de verdad

**El fix:** el umbral de movimiento para aplicar daño subió de 0.3 a 0.8 tiles. Si el NPC
no se movió al menos 0.8 tiles desde donde empezó la trepada, no recibe daño. Un jugador,
zombie o mueble bloqueando la salida impide ese movimiento → sin daño.

1. Buscá una ventana con vidrios rotos.
2. Ponete del otro lado para bloquear la salida.
3. Hacé que el NPC intente cruzar.
4. **Esperado:** el NPC intenta trepar, no puede cruzar, y **no recibe daño**. En el log
   NO debe aparecer `WOUND ... cut on broken glass`.
5. Ahora despejá el otro lado y hacé que cruce. **Esperado:** recibe daño normalmente.
   En el log: `WOUND ... cut on broken glass at X,Y | window-climb`.

---

### P20 — PANIC: sin jumpscare al iniciar juego ni al girar hacia un NPC

**El fix:** la supresión de pánico ahora arranca en el primer tick (antes tardaba ~6s hasta
que corriera el sweep). Además, si el pánico se dispara y el área solo tiene aliados, se
re-chequea al instante (cooldown 1s) en vez de esperar al siguiente sweep.

1. Iniciá una partida con un compañero al lado.
2. **Esperado:** no debe aparecer el moodle de pánico ni el sonido de jumpscare.
3. Alejate del NPC, girá la cámara para no verlo, y volvé a mirarlo de repente.
4. **Esperado:** sin jumpscare. El NPC es un aliado, no un zombie.
5. Buscá en el log: si aparece `PANIC spike`, es que el motor metió pánico Java-side
   y nuestro sistema lo detectó. No debería haber spikes nuevos.

---

### P22 — Climb: el NPC trepa rejas y muros altos

**El fix:** el watchdog ahora usa `zombie:climbOverFence(dir)` y `zombie:climbOverWall(dir)`
— los métodos del motor que usa el jugador. Cada método tiene su propia sonda one-time:
si falla en IsoZombie, se loguea una sola vez.

1. Buscá una reja entre vos y un compañero. Alejate al otro lado.
2. **Esperado:** el NPC debe caminar hacia la reja e intentar treparla. En el log:
   `engine climb climbOverFence`.
3. Buscá un muro alto (tall fence). Repetí.
4. **Esperado:** en el log: `engine climb climbOverWall`.
5. Si el NPC no trepa, buscá en el log si apareció `climbOverFence threw` o
   `climbOverWall threw` — si sale, el método no es llamable en IsoZombie.

---

### P24 — Ventana fija: el NPC la rompe para atacar

**El fix:** cuando el NPC está en combate (Smack/Push) trabado en una ventana, el watchdog
ahora detecta `blocked by window` y queuea `SmashWindow` directamente (sin esperar
OpenWindow ni el cooldown de 8 sweeps).

1. Buscá una casa con un zombie adentro y una ventana fija (de baño, por ejemplo).
2. Llevá un compañero cerca. El zombie debería golpear la ventana.
3. **Esperado:** el NPC camina hacia la ventana, apunta al zombie, y al detectar que
   está bloqueado por `window`, queuea `SmashWindow`. Rompe la ventana y ataca.
4. En el log: `blocked by window -- combat, queued SmashWindow`.

---

### P25 — Health panel: menú derecho, congelar NPC, auto-close, animación de vendaje

**El fix:** cuatro mejoras de UX sobre el panel de salud.

1. **Nombres en inglés:** click en parte herida → los textos dicen "Laceration",
   "Scratched", "Deep Wound", etc. (no "laceración" en español).
2. **Menú derecho:** hover sobre el texto de herida → click derecho → "Bandage"
   (si necesitás venda y tenés una) o "Change bandage" (si la venda está sucia).
3. **NPC congelado:** al abrir Health el NPC se congela (`Bandit.ForceStationary`).
   No debería moverse mientras lo examinás.
4. **Auto-close:** si te movés más de 0.5 tiles con el menú abierto, se cierra solo.
5. **Animación de vendaje:** al clickear Bandage, aparece "Bandaging... 3s" con un
   timer. Si cerrás el menú antes de que termine, se cancela (no gasta la venda).

---

## Qué NO hace falta que reportes

- el loot no entra a la mochila;
- juntan lapiceras y cucharas;
- el compañero se congela frente a una ventana estando adentro;
- el miedo cuenta zombis a través de paredes;
- un NPC cerca te levanta del sofá (verificado: no alcanzable desde Lua).
