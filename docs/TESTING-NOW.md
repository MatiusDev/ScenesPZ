# ► Probá esto

**Esta página se REESCRIBE entera cada corrida.** No se le agrega nada. Lo que se cierra se
muda a [`docs/TEST-LOG.md`](TEST-LOG.md) y desaparece de acá.

> **Se rompió esa regla y se está arreglando ahora.** Las corridas del 09 y el 10 se fueron
> apilando como secciones nuevas —"la importante de esta tanda", "nuevas de la tanda anterior"—
> hasta doce pruebas de las cuales seis ya habían pasado. Esa acumulación es exactamente el
> mecanismo de podredumbre que documentamos: los archivos a los que se les *agrega* sobreviven,
> los que hay que *reescribir* se pudren porque nadie reescribe. Todo lo cerrado está ahora en
> el TEST-LOG.

> Español porque lo leés con el juego abierto. Todo lo demás sigue en inglés.

---

## Corrida abierta: 10-08 — qué está trabando a los NPC

**Una sola pregunta esta vez.** No hay comportamiento nuevo que probar: lo que se agregó es un
diagnóstico. Lo que necesito de vos son datos, no un veredicto.

### Antes de arrancar

1. **Steam: desuscribir y volver a suscribir Bandits.** Slayer publicó una actualización el 10-08
   y tu copia tiene que coincidir con la que yo leo.
2. `git pull`.
3. `./tools/hooks/install.sh` (una sola vez, nunca más).
4. En `console.txt` tiene que decir `ASSERT ---- 30 ok, 0 FAILED ----`. Si alguna dice `FAIL`,
   pará y mandámela.

### P12 — la única que importa

Jugá normal un rato con compañeros, **con edificios cerca**: entrando y saliendo de casas,
patios con rejas, calles con cercos. Después buscá en `console.txt`:

```
AUTO <nombre> | stuck on Move@x,y for 2 sweeps without moving -- blocked by <QUÉ> -- queue cleared
```

**Contame la proporción de ese último campo.** Los valores posibles:

| Valor | Qué significa |
|---|---|
| `door` | una puerta cerrada sin llave — se podría abrir |
| `locked` | una puerta con llave — por ahí no se pasa |
| `hop` | una reja baja — se podría trepar |
| `tall` | una reja alta — se podría trepar, más lento |
| `solid` | una pared, o algo sobre lo que no se puede actuar |
| `clear` | se trabó pero la línea estaba despejada — sospechoso, avisame |
| `probe threw` | el diagnóstico falló — mandámelo, es un bug mío |

**Por qué esto decide el próximo trabajo.** Si casi todo sale `solid`, escribir una acción de
puerta no arregla nada y el trabajo real es otro. Si domina `door`, sé exactamente qué construir.
Hoy estaríamos adivinando, y adivinar ya costó dos reversiones esta semana.

### P13 — la sonda de puertas (de la corrida anterior, sin responder)

Parate **a menos de 6 tiles de una puerta** y arrancá. Buscá:

```
PROBE door | isExterior ok=... value=...
PROBE door | isExteriorDoor ok=... value=...
PROBE blocks | E/W/N/S = ...
```

**Mandame las tres textuales, digan lo que digan.** `ok=false` **también es una respuesta** y
cambia el diseño; no es un fallo tuyo.

Tu orden de entrada dice *"la siguiente puerta **exterior**"*. Esos dos métodos existen en la
clase compilada del juego pero **ningún archivo Lua de vanilla los llama** — la misma forma que
`getSeeNearbyCharacterDistance`, que copiamos de código muerto y costó una sesión entera. Si no
se pueden llamar, la regla hay que rehacerla en términos geométricos.

Si sale `SKIPPED`, acercate más a la puerta y reiniciá.

---

## Qué NO hace falta que reportes

Todo lo de [`TODO.md`](TODO.md) ya está anotado. Lo más grande, para que no lo busques:

- **el loot no entra a la mochila** — no es persistencia, es que el cadáver se arma con
  `getAllEvalRecurse`, que aplana los contenedores;
- **juntan lapiceras y cucharas** — el motor las declara `base:weapon`, así que nuestro filtro es
  técnicamente correcto e inútil;
- el compañero se congela frente a una ventana estando ya adentro;
- el miedo cuenta zombis a través de paredes, y con seis huyen todos sin importar cuántos sean;
- un NPC cerca te levanta del sofá (**verificado: no alcanzable desde Lua**);
- daño por parte del cuerpo: quedan inválidos con la salud al 100%.

## Qué NO probar todavía

Huida y reenganche. El modelo de miedo tiene un defecto conocido y documentado, y sale con el
paso 5 del plan.
