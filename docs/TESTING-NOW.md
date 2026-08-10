# ► Probá esto

**Esta página se REESCRIBE entera cada corrida.** No se le agrega nada. Lo que se cierra se
muda a [`docs/TEST-LOG.md`](TEST-LOG.md) y desaparece de acá.

El razonamiento completo de por qué cambió cada cosa está en
[`docs/PLAN-FIXES-09-08.md`](PLAN-FIXES-09-08.md). Acá solo está qué hacer.

---

## Corrida abierta: 09-08 noche — solo la mitad segura

**Esta corrida es deliberadamente corta.** El diff estaba partido en dos mitades y la mitad
riesgosa tenía defectos severos confirmados por revisión. Se arregló lo peor de esa mitad, pero
**no se prueba todavía**: huida, reenganche y el loot con chequeo de pared quedan fuera.

### Antes de arrancar

1. `git pull` en la PC de juego.
2. `ASSERT ---- 24 ok, 0 FAILED ----` (bajó de 25 a propósito, ver P0) en `console.txt`. Si algo dice `FAIL`, pará y mandámelo.

### Las pruebas

| # | Qué hacer | Pasa si |
|---|---|---|
| **P0** | Arrancá y buscá `Lua fail` / `KahluaUtil` en `console.txt`. | **No aparece ninguno.** Ese stack trace lo generaba una aserción nuestra: llamaba a un método inexistente dentro de un `pcall` para comprobar que seguía sin existir. El `pcall` lo atrapaba y la prueba pasaba, pero el motor imprimía igual su propia traza Java. Fue eliminada, por eso ahora son 24 y no 25. |
| **P1** | Dale una mochila a un NPC y quedate mirándolo **sin alejarte**. | Se le ve puesta sin descargar y recargar. Si no se ve, mandame igual la línea `LOOT ... wears the ...` — significa que el redibujado en vivo no se puede desde Lua y hay que diseñar alrededor. |
| **P2** | Parate pegado a tus compañeros, sin zombis, y **mirá de golpe** a uno. | **Ni un parpadeo** del moodle de pánico. |
| **P3** | Sesión larga; después buscá `PANIC` en el log. | No aparece `fast suppression is OFF`. Si aparece, mandámelo: el pánico pudo quedar apagado. |
| **P4** | Lootea con un NPC y después matalo. | El log lista **qué** ítems tomó: `LOOT ... took 3 from x,y [Base.TinnedBeans, ...]`. El cadáver debería coincidir. |
| **P5** | Miralos cuando estén cansados. | Se sientan **solo** por cansancio. No debería quedar ninguna línea `the lazy sort`. |

### Qué NO probar todavía

Huida y reenganche, y el rechazo de loot por pared. Están arreglados a medias a propósito — el
modelo de miedo todavía tiene un defecto conocido (con seis zombis huyen todos, sin importar
cuántos sean ustedes) y sale en la próxima.

### Lo que ya sé que sigue roto

Todo en [`TODO.md`](TODO.md). No hace falta que lo reportes de nuevo. Lo más grande:

- **el bolso no se usa nunca** — se llenan el inventario general al 139% y nada entra a la mochila;
- el compañero se congela frente a una ventana estando ya adentro;
- el miedo cuenta zombis a través de paredes;
- un NPC cerca te levanta del sofá (verificado: no arreglable desde Lua);
- daño por parte del cuerpo: quedan inválidos con la salud al 100%.
