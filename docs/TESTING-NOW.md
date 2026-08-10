# ► Probá esto

**Esta página se REESCRIBE entera cada corrida.** No se le agrega nada. Lo que se cierra se
muda a [`docs/TEST-LOG.md`](TEST-LOG.md) y desaparece de acá.

> Español porque lo leés con el juego abierto. Todo lo demás sigue en inglés.

---

## Corrida abierta: 10-08b — vidrios rotos y pánico (jumpscare)

**Dos fixes, los dos con logs nuevos para validar.** También están P14-P18 de la corrida
anterior por si querés volver a probarlas.

### Antes de arrancar

1. `git pull`.
2. En `console.txt` buscá `ASSERT ---- 30 ok, 0 FAILED ----`. Si alguna dice `FAIL`, pará.
3. Apenas cargue, confirmá que estos módulos cargaron:
   ```
   WOUND ready -- healing costs a dressing; broken glass costs blood; window-open hook catches crossings the sweep misses
   PANIC ready -- your own people no longer read as a horde; spike detector active (logs jumpscares)
   ```
   Si alguno falta, el módulo no cargó.

---

### P19 — vidrios rotos al cruzar una ventana

**El fix:** ahora cuando un NPC abre una ventana, el hook verifica si el marco tenía vidrios
rotos y aplica el corte en ese momento. Antes solo se detectaba si el NPC se quedaba parado en
el marco durante un sweep (~6 segundos). El hook lo atrapa en el momento exacto de abrir.

1. Encontrá una ventana con vidrios rotos (casa abandonada, o rompela vos).
2. Hacé que un compañero la abra y la cruce.
3. Buscá en `console.txt`:

   ```
   WOUND <nombre> cut on broken glass at X,Y | X.XX -> X.XX / X.XX | window-open
   ```

   - `window-open` = el hook lo agarró al abrir la ventana
   - `sweep` = el checker del sweep lo detectó (el mecanismo viejo, sigue funcionando)

4. **Esperado:** el NPC recibe daño. La vida baja ~0.25. Si cruza varias ventanas seguidas
   sin descanso, el cooldown (`CUT_COOLDOWN = 10` sweeps) evita que se destroce.

5. **Repetí entrando y saliendo** por la misma ventana. El daño debería aplicar en ambas
   direcciones.

6. Si ves `WOUND ... cut on broken glass ... sweep` pero NUNCA `window-open`, el hook no está
   disparando — avisame.

### P20 — pánico por mirar a un NPC (jumpscare)

**El fix NO es un fix — es un detector.** El motor de PZ puede estar metiendo pánico
directamente al jugador cuando un NPC amigo aparece cerca o en línea de visión, porque para
el motor un NPC **es** un zombie (`IsoZombie`). Nuestra supresión controla la tasa de
incremento y el stat, pero el motor puede saltárselos con un bump directo.

El spike detector revisa cada ~6 segundos si el stat de pánico subió a pesar de que solo hay
amigos cerca. Si lo detecta, lo loguea.

1. Jugá normal con un compañero cerca.
2. Hacé que el compañero aparezca de repente frente a vos (que venga corriendo, que doble
   una esquina, que abra una puerta y te lo encuentres de golpe).
3. Buscá en `console.txt`:

   ```
   PANIC spike #1 detected | stat=X despite suppression active | max seen this session=Y
   ```

4. **Si aparece:** el jumpscare es real. El número `stat=X` me dice la magnitud. Mandame la
   línea completa.

5. **Si NO aparece en una sesión larga con varios encuentros cercanos:** el detector no está
   capturando nada — puede ser que el spike sea más rápido que el sweep (el detector corre
   cada ~6s, igual que el sweep) o que el motor no esté generando pánico por NPCs en esta
   build. En cualquier caso, también es un dato.

### P14–P18 — follow, resistencia, rango (de la corrida anterior)

**Ya fueron verificadas en la corrida del 10-08.** Si querés volver a probarlas con los
cambios nuevos, adelante. Lo que se confirmó:

| Prueba | Veredicto corrida anterior |
|---|---|
| P14 — follow al trotar | ✅ `master running` aparece, locks activos |
| P15 — no se queda pegado | ✅ cero `combat took the last follow`, locks protegen |
| P16 — te sigue lejos | ✅ `found again at X tiles` × 4, pero se traba en obstáculos |
| P17 — resistencia | ✅ ciclo winded→sit→rested confirmado |
| P18 — telemetría | ✅ `chase over` 30+, `found again` 4, `caught up` 3 |

---

## Qué NO hace falta que reportes

Todo lo de [`TODO.md`](TODO.md) ya está anotado:

- el loot no entra a la mochila;
- juntan lapiceras y cucharas;
- el compañero se congela frente a una ventana estando adentro;
- el miedo cuenta zombis a través de paredes;
- un NPC cerca te levanta del sofá (verificado: no alcanzable desde Lua).

## Qué NO probar todavía

Huida y reenganche con matemática de grupo. El modelo de miedo tiene un defecto conocido
(no tiene línea de visión), y sale con el paso 5 del plan.
