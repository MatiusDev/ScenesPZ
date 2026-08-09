# Dónde estamos

Página índice. Corta a propósito: **si algo acá crece más de una pantalla, va a otro archivo.**

> **Nota de idioma.** Este archivo va en español porque es el que usás mientras jugás.
> Todo el resto — código, comentarios, planes, commits — sigue en inglés.

| Necesitás | Andá a |
| :--- | :--- |
| **Qué probar ahora** | [`docs/TESTING-NOW.md`](TESTING-NOW.md) — se reescribe entera cada corrida |
| Qué ya se probó y qué aprendimos | [`docs/TEST-LOG.md`](TEST-LOG.md) — solo crece, nunca se corrige hacia atrás |
| La hoja de ruta completa | [`docs/plans/README.md`](plans/README.md) |
| Cosas vistas en juego que ninguna etapa reclamó | [`docs/TODO.md`](TODO.md) |

---

## Cómo trabajamos

Un bloque a la vez. Cada bloque son 2–3 cosas que **comparten causa**, no 12 sueltas. No abrimos
el siguiente hasta que el actual pase.

Esto se decidió porque funciona: la corrida del 04-08 dejó 1.422 líneas de log y **una sola
causa** explicaba cuatro de los síntomas. La del 09-08 repitió el patrón — "solo revisa algunos
cajones" y "se traba en las puertas" resultaron ser el mismo defecto.

---

## Bloques

| Bloque | Estado |
|---|---|
| **A — lo que recogen es de verdad** | ✅ **cerrado el 09-08.** Veredicto por prueba en el log. |
| **A′ — mochila que se ve y que sirve, y el pánico** | 🔵 **abierto, esperando tu corrida.** Ver `TESTING-NOW.md`. |
| **B — entrar a un edificio** | ⏭ **el que sigue, y es el grande.** Sin empezar. |
| **C — seguir y huir con matemática de grupo** | especificado, sin empezar |
| **D — postergados** | ver abajo |

### B — entrar a un edificio

**Es el que te está rompiendo la partida.** El log del 09-08 lo prueba con números: 111
abandonos por no poder llegar contra 15 muebles abiertos. Desbloquea el looteo completo, la
autonomía de los NPC libres, y que dejen de trabarse contra puertas y ventanas.

El orden lógico, que es tuyo y es correcto:

1. Intentar **la puerta** más cercana.
2. Si está bloqueada, **la ventana** más cercana.
3. Si ninguna sirve, **dar la vuelta** al edificio.
4. Si aparecen zombies en el intento, **dejar de entrar y limpiar la zona** primero.
5. Si vos entraste por una ventana, **priorizar esa misma entrada**.
6. **Romper la puerta solo como última instancia**, cuando todo lo demás está bloqueado.

Lo que ya sabemos antes de diseñar:

- **Bandits trae `ZAOpenWindow`, `ZASmashWindow`, `ZAClimbFence` — y ninguna acción de puerta.**
- **The Ark no aporta nada acá.** Sus 27 acciones son vida doméstica.
- `GetAccessSquare` devuelve casillas inalcanzables: Slayer dejó el chequeo comentado
  (`42.20/BanditUtils.lua:1051`). `canReachTo` es real pero **solo valida adyacencia**.

Va junto con la percepción: hoy saben dónde está cada zombie porque
`GetClosestZombieLocation` **no tiene límite de distancia**. Deberían sorprenderse.

### C — seguir y huir con matemática de grupo

Tu descripción es la especificación:

> *"quiere volver a mi porque me está siguiendo, pero ve los zombies y luego huye. Se queda en
> ese estado de correr y volver, correr y volver."*

- **3+ zombies sobre un solo NPC (o sobre vos solo)** → reposicionarse y pelear desde distancia.
- **2+ de los nuestros contra 3 zombies** → nadie se mueve, se pelea.
- Grupo chico (2–3): el que no llega **espera y llama**. Llamar hace ruido y atrae más zombies —
  es un costo real.
- Grupo grande (4+) con horda encima: huyen todos.

Falta el conteo de gente **nuestra** cerca; hoy la escalera solo cuenta zombies.

### D — postergados, con razón

| Qué | Por qué espera |
|---|---|
| No se cura solo | Necesita vendas en el inventario. |
| Ventana disputada, leer | Los bajaste de prioridad vos mismo. |
| ¿Descansan de verdad? | La resistencia solo baja en Bandits; nuestro descanso es la única fuente. |
| Los sueltos siguen en idle | Bloqueado por B: un NPC autónomo que no cruza una puerta falla más visiblemente que uno quieto. Diseño en `03-autonomy.md`, y las 27 acciones domésticas de The Ark son el material. |
| Disciplina de fuego y el flag grupal de "no hagamos ruido" | Bloqueado por B, y detallado en `TODO.md`. |
| No aparece compañero al revivir | **El log dice que sí se pide**: 3 respawns, 3 × `TLOU\| companion requested`, ningún NPC. El fallo está **adentro de `BanditServer.Spawner.Clan`**. |

---

## En qué etapa va cada plan

| Etapa | Estado |
|---|---|
| [00 — Mundo de pruebas](plans/00-test-world.md) | construida, confirmada a medias |
| [01 — Memoria durable](plans/01-durable-memory.md) | **confirmada** |
| [02 — Rueda de interacción](plans/02-interaction-wheel.md) | **confirmada** |
| [03 — Autonomía](plans/03-autonomy.md) | bloque A cerrado; B sin empezar |
| [Heridas y curación](plans/wounds-and-healing.md) | etapa 1 construida; conversión **apagada** a propósito |

---

## Deuda que no es de ningún bloque

- El kit de prueba en `TLOUFactionsCompanion.lua` es **temporal** y hay que borrarlo.
- `SR.DEBUG` tiene que quedar en `false` antes de publicar.
- Nunca llamamos `Bandit.ForceSyncPart` después de mutar el estado de loot — defecto de
  multijugador que el smoke test **no puede ver por construcción**.
