# ► Probá esto

**Esta página se REESCRIBE entera cada corrida.** No se le agrega nada. Lo que se cierra se
muda a [`docs/TEST-LOG.md`](TEST-LOG.md) y desaparece de acá.

Si esta página y cualquier otra se contradicen, ésta es la que está vieja — arreglala.

> **Nota de idioma.** Este archivo va en español porque es el que usás mientras jugás.
> Todo el resto — código, comentarios, planes, commits — sigue en inglés.

---

## Corrida abierta: 09-08 — mochila que se ve, mochila que sirve, y dejar de tenerte miedo

### Antes de arrancar

1. `git pull` en la PC de juego. **La corrida anterior se probó con código viejo una vez ya.**
2. Desuscribite y resuscribite de **Bandits** y **Week One** en Steam. Se actualizaron los dos.
3. Personaje **nuevo** si vas a mirar el kit de prueba o el compañero inicial.

### Primero, siempre

Buscá `ASSERT` en `console.txt`. Tiene que decir:

```
ASSERT ---- 24 ok, 0 FAILED ----
```

**Si algo dice `FAIL`, pará ahí y mandámelo.** El motor no tiene la forma que el código cree, y
ninguna observación de abajo significa nada hasta arreglar eso.

### Las pruebas

| # | Qué hacer | Pasa si |
|---|---|---|
| **B1** | Personaje nuevo. Mirá el inventario. | Seis mochilas, pistola y **dos cargadores**. Log: `test kit given -- 10 of 10 items`. La pistola por fin dispara. |
| **B2** | Dale una mochila a un NPC y **quedate mirándolo**, sin alejarte. | **Se le ve puesta en la espalda al instante.** Antes solo aparecía si se despawneaba y volvía. |
| **B3** | Dale la riñonera (cap. 1) a uno y el framepack (cap. 35) a otro. Que looteen la misma casa. | El del framepack aguanta muchísimo más antes de `stops searching -- full`. La línea trae `carrying X / Y` — **la Y tiene que ser muy distinta entre los dos**. Si son iguales, la capacidad no se conectó. |
| **B4** | Parate pegado a tus compañeros, sin zombis cerca. | **No sube el pánico.** Si aparece un zombi o un bandido hostil, vuelve a subir normal. |
| **A7** | Tirá una prenda al piso cerca de un NPC **libre** (no compañero). Esperá 2–3 minutos de juego. | Camina, la levanta y se la pone. **Si ves `IDLE ... gave up on ...` repetido, el arreglo no funcionó.** Quedó sin probar de la corrida anterior. |

### Qué NO hace falta que mires

Ya pasó el 09-08 y está cerrado en el log: que se acerquen al mueble antes de abrirlo, que no
aparezca `LOOT refused`, que lo que agarran sirva, que suelten lo recogido al morir.

### Qué ya sé que sigue roto

**No hace falta que lo reportes de nuevo.** Que se traben contra puertas y ventanas, y que dejen
muchos muebles sin revisar. Son **la misma causa** — 111 abandonos por no poder llegar en el
último log — y es el bloque que sigue, el grande.

### Qué mandarme

`console.txt` y una línea por prueba. Si algo falla, la línea del log que lo muestra.

---

## Qué entró en esta corrida

- **La mochila ahora se ve.** No era el modelo: `ApplyVisuals` ya llama `resetModel()`
  (`Bandit.lua:280`). Era que la mochila entraba a la lista visual pero **nunca se equipaba** —
  Slayer dejó comentada la línea que lo hace (`Bandit.lua:249`). La ponemos nosotros, con
  `canBeEquipped()` y no `getBodyLocation()`, porque vanilla resuelve ese caso exacto así en
  `ISInventoryPaneContextMenu.lua:1690`.
- **La mochila ahora sirve.** Antes no daba **nada** de capacidad: el presupuesto salía del
  inventario principal, y en PZ una mochila es un contenedor aparte. `Loot.CarryBudget` le suma
  `getItemContainer():getMaxWeight()`. Cadena verificada en `FenrisScenario.lua:409`.
- **Tus propios NPC ya no te dan miedo.** Un Bandit *es* un `IsoZombie`, así que el modelo de
  pánico del motor los contaba como horda. Slayer escribió el arreglo y lo dejó apagado
  (`BanditPlayer.lua:132`, `if true then return end`). El nuestro es propio, no toca el suyo.
- **Kit de prueba: seis mochilas de capacidad 1 a 35**, y la pistola con dos `Base.9mmClip` —
  declara `MagazineType`, así que la caja de balas sola nunca alcanzó.
- 5 aserciones nuevas (**24** en total).
