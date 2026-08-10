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
2. `ASSERT ---- 28 ok, 0 FAILED ----` — subió de 24: cuatro sondas de puerta nuevas (P11) en `console.txt`. Si algo dice `FAIL`, pará y mandámelo.

### Las pruebas

| # | Qué hacer | Pasa si |
|---|---|---|
| **P0** | Arrancá y buscá `Lua fail` / `KahluaUtil` en `console.txt`. | **No aparece ninguno.** Ese stack trace lo generaba una aserción nuestra: llamaba a un método inexistente dentro de un `pcall` para comprobar que seguía sin existir. El `pcall` lo atrapaba y la prueba pasaba, pero el motor imprimía igual su propia traza Java. Fue eliminada, por eso ahora son 24 y no 25. |
| **P1** | Dale una mochila a un NPC y quedate mirándolo **sin alejarte**. | Se le ve puesta sin descargar y recargar. Si no se ve, mandame igual la línea `LOOT ... wears the ...` — significa que el redibujado en vivo no se puede desde Lua y hay que diseñar alrededor. |
| **P2** | Parate pegado a tus compañeros, sin zombis, y **mirá de golpe** a uno. | **Ni un parpadeo** del moodle de pánico. |
| **P3** | Sesión larga; después buscá `PANIC` en el log. | No aparece `fast suppression is OFF`. Si aparece, mandámelo: el pánico pudo quedar apagado. |
| **P4** | Lootea con un NPC y después matalo. | El log lista **qué** ítems tomó: `LOOT ... took 3 from x,y [Base.TinnedBeans, ...]`. El cadáver debería coincidir. |
| **P5** | Miralos cuando estén cansados. | Se sientan **solo** por cansancio. No debería quedar ninguna línea `the lazy sort`. |

### La que desbloquea el bloque de puertas

| # | Qué hacer | Pasa si |
|---|---|---|
| **P11** | **Parate cerca de una casa** (a menos de 6 tiles de una puerta) y arrancá. Buscá `PROBE door` en `console.txt`. | Salen dos líneas: `isExterior ok=... value=...` y `isExteriorDoor ok=... value=...`. **Mandame las dos textuales**, digan lo que digan. Si dicen `ok=false`, eso es la respuesta y cambia el diseño — no es un fallo tuyo. Si alguna dice `SKIPPED`, alejate menos de la puerta y reintentá. |

**Por qué importa tanto una línea de log:** tu orden de entrada dice *"la siguiente puerta
**exterior**"*. Esos dos métodos existen en la clase compilada del juego, pero **ningún archivo
Lua de vanilla los llama** — que es exactamente la forma de `getSeeNearbyCharacterDistance`, el
método que copiamos de código muerto y nos costó una sesión entera. Si no se pueden llamar desde
Lua, la regla hay que rehacerla en términos geométricos. El motor contesta esto en un arranque; yo
no lo puedo contestar desde acá.

### La importante de la tanda anterior

| # | Qué hacer | Pasa si |
|---|---|---|
| **P10** | Dale una mochila a un NPC **que ya esté a la vista** y no te muevas. | **Se le ve puesta, ahí mismo.** Si sale `LOOT put the skin back by hand`, mandámelo: significa que funcionó pero el brain no traía piel que restaurar. Si el NPC queda con un aspecto roto o invisible, avisame **de inmediato** — sería la red de seguridad fallando y se revierte en un minuto. |

Antes de esto hacía falta alejarse y volver. La causa no era el motor: `Bandit.ApplyVisuals`
tiene una guarda arriba que lo hace **salir sin hacer nada** si la piel del NPC es una textura
normal de cuerpo — o sea, siempre que ya esté vestido y a la vista. Llamábamos a la función
correcta y se negaba a correr.

### Nuevas de la tanda anterior

| # | Qué hacer | Pasa si |
|---|---|---|
| **P6** | Matá un NPC que tenga mochila y contá las mochilas en el cadáver. | **Una sola.** Dos era la regresión que reportaste. |
| **P7** | Miralo con la mochila puesta. | Ya **no** se ve al instante, y eso es lo esperado: aparece cuando el NPC se descargue y recargue por juego normal. Si **nunca** aparece, decímelo — significaría que ni siquiera se está escribiendo en el brain, que es un problema distinto. |
| **P8** | Caminá y corré con un compañero siguiéndote, un rato largo. | Se mantiene cerca en vez de llegar siempre a donde estabas. Buscá `fast follow` en el log. |
| **P9** | Poné a un NPC a lootear una casa y **alejate** para que tenga que seguirte. | Te sigue **y** conserva lo que estaba haciendo. Lo que hay que vigilar: que al terminar de seguirte **no** se vuelva caminando al mueble que dejó. Si lo hace, mandámelo — es el riesgo conocido de este cambio. |

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
