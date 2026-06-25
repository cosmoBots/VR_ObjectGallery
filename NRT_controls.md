# NRT Controls

Este documento resume los controles actuales del programa. La columna "teclado" describe la simulacion Linux/desktop cuando OpenXR no esta activo.

## Hardcodeada independiente del YAML

| Funcion | Control VR | Teclado / raton | Reaccion |
| --- | --- | --- | --- |
| Capturar raton | No aplica | Click izquierdo | Captura el raton para mirar en modo desktop. |
| Liberar raton | No aplica | Esc o click derecho | Libera el raton en modo desktop. |
| Mirar en desktop | No aplica | Movimiento de raton capturado | Rota la camara desktop. |
| Mover adelante/atras en desktop | No aplica | W / S | Desplaza la camara desktop. |
| Mover lateral en desktop | No aplica | A / D | Desplaza la camara desktop. |
| Avanzar/retroceder en XR | Stick izquierdo vertical | Sin equivalente de locomocion desktop; K / I solo simulan `left_stick_y` para bindings | Mueve el origen XR hacia delante o atras en visor. En Linux usa W / S para mover la camara. |
| Girar en XR | Stick izquierdo horizontal | Sin equivalente de locomocion desktop; J / L solo simulan `left_stick_x` para bindings | Rota el origen/camara en visor. En Linux usa el raton capturado para mirar/girar. |
| Strafe lateral en XR | Grip izquierdo + stick izquierdo horizontal | Sin equivalente de locomocion desktop; C + J / L solo simula botones/ejes | Desplaza lateralmente el origen XR en visor. En Linux usa A / D para mover la camara. |
| Subir/bajar altura | Grip izquierdo + stick izquierdo vertical | E / Q, R / F, PageUp / PageDown | En visor sube/baja el origen XR. En Linux sube/baja la camara desktop. |
| Reset de altura | Click stick izquierdo (`left_stick_click`) | U | Devuelve la altura al nivel inicial en visor o en Linux desktop. |
| Alternar AR/VR | `left_by_button`; en Vive tambien gatillo derecho | B; solo tiene efecto AR/VR en XR real | Cambia entre AR y VR, salvo si `disable_ar: true`. |
| Alternar dia/noche | Grip izquierdo + `left_by_button`; en Vive tambien grip izquierdo + gatillo derecho | C + B | Alterna `illumination` entre `day` y `night`. |
| Filtro/vista izquierda | `left_ax_button`; en Vive tambien `select_button` izquierdo | 1 | Activa vistas filtradas que usen `button: "left_ax_button"` en YAML. |
| Boton AX derecho | `right_ax_button` | 2 | Disponible como binding para YAML/depuracion. |
| Gatillo izquierdo | `left_trigger_click` o valor analogico `trigger` | Y | Ilumina la varita izquierda; disponible como binding. |
| Gatillo derecho | `right_trigger_click` o valor analogico `trigger` | P | Ilumina la varita derecha; disponible como binding. |
| Grip izquierdo | `left_grip_click` o valor analogico `grip` | C | Modificador de vuelo y dia/noche; disponible como binding. |
| Grip derecho | `right_grip_click` o valor analogico `grip` | V | Disponible como binding. |
| Stick derecho X | Stick derecho horizontal | Flechas izquierda/derecha | Excepcion fija: simula `right_stick_x` para controles YAML. |
| Stick derecho Y | Stick derecho vertical | Flechas abajo/arriba | Excepcion fija: simula `right_stick_y` para controles YAML. |
| Stick derecho click | Click stick derecho (`right_stick_click`) | Solo via `reset_key` en controles YAML | En XR resetea controles cuyo `reset_binding` sea `right_stick_click`. |
| Secondary izquierdo X | Eje `secondary` izquierdo X | F / H | Disponible como binding local. |
| Secondary izquierdo Y | Eje `secondary` izquierdo Y | G / T | Disponible como binding local. |
| Secondary izquierdo click | `left_secondary_click` | 7 | Disponible como binding local. |
| Secondary derecho X/Y/click | `right_secondary_x`, `right_secondary_y`, `right_secondary_click` | Configurable por YAML si se usa en controles | No tiene teclas hardcodeadas, salvo que cada control defina teclas. |

Notas:
- `disable_ar: true` bloquea cualquier intento de activar AR.
- En desktop, `J/L` y `K/I` no mueven la camara por si solos: solo alimentan la simulacion de `left_stick_x/y` para bindings que lean esos ejes. Para navegar en Linux se usan W/A/S/D, raton y las teclas de subir/bajar.
- En desktop, los controles AR/VR no cambian AR/VR real; `C + B` si permite alternar dia/noche para previsualizar iluminacion.
- Los bindings de mano izquierda no son configurables por YAML.

## Definida en YAML

### Ajustes globales de `models/models.yaml`

| Clave | Valor actual | Reaccion |
| --- | --- | --- |
| `default_ar` | `false` | Define si la app intenta arrancar en AR. |
| `disable_ar` | `true` | Fuerza VR y bloquea el cambio manual a AR. |
| `texture_sky` | `"eso_milky_way_panorama.jpg"` | Carga la textura panoramica del cielo desde `res://assets/sky/` si se usa un nombre simple. |
| `illumination` | `"night"` | Modo de iluminacion inicial: `day` o `night`. |
| `floor_size` | `[80.0, 80.0]` | Tamano del suelo en metros. |
| `day_illum.ambient_light_energy` | `0.28` | Luz ambiente del modo dia. |
| `day_illum.directional_light_energy` | `2.2` | Potencia de la luz direccional del modo dia. |
| `night_illum.ambient_light_energy` | `2.94` | Luz ambiente del modo noche. |
| `night_illum.directional_light_energy` | `0.24` | Potencia de la luz direccional tipo luna. |

### Vistas filtradas

| Modelo | Accion YAML | Control VR | Teclado | Reaccion |
| --- | --- | --- | --- | --- |
| `BancoIFU.glb` | `filtered_views.view1` | `left_ax_button` | 1 | Alterna la vista filtrada del grupo Godot `optics`; publica MQTT si esta habilitado. |

### Controles de modelos

| Modelo | Accion YAML | Control VR | Teclado | Reaccion |
| --- | --- | --- | --- | --- |
| `NRT.glb` | `yaw` | `right_stick_x` | Flechas izquierda/derecha | Rota `Telescope` en eje global Y, rango `-270..270`, velocidad `90`. |
| `NRT.glb` | `pitch` | `right_stick_y` | Flechas abajo/arriba | Rota `Telescope_Structure` en eje local X, rango `-45..22`, velocidad `45`. |
| `BancoIFU.glb` | `polarimeter` | `right_stick_x`; reset con `right_stick_click` | Flechas izquierda/derecha; reset con O (`reset_key`) | Mueve `44V-M70-460_POLARIMETRO_ASS_ASM` en eje X, rango `-0.08..0.17`, velocidad `-0.10`. |
| `BancoIFU.glb` | `fm1` | `right_stick_y`; reset con `right_stick_click` | Flechas abajo/arriba; reset con O (`reset_key`) | Mueve `44V-M70-511_MOUNTANDBASE` en eje Z, rango `-0.01..0.02`, velocidad `-0.10`. |

Campos de teclado configurables por control:
- `keyboard_negative`: tecla para entrada negativa del eje.
- `keyboard_positive`: tecla para entrada positiva del eje.
- `reset_key`: tecla para simular el reset de ese control.

Excepciones:
- `right_stick_x` siempre usa flechas izquierda/derecha en desktop.
- `right_stick_y` siempre usa flechas abajo/arriba en desktop.
- Si un control usa otro `local_ctrl` de mano derecha, su teclado debe definirse en el propio control con `keyboard_negative`, `keyboard_positive` y/o `reset_key`.
