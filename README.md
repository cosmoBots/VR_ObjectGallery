# VR Object Gallery (Godot 4.6)

Proyecto VR base para mostrar automaticamente todos los objetos de una carpeta en una habitacion, colocados en cuadricula.

## Formato recomendado desde BlockBench

**Recomendado: `glTF Binary (.glb)`**

Motivos:
- Conserva mallas, materiales y jerarquia.
- Un solo archivo por objeto (mas comodo que `.gltf + bin + texturas`).
- Importacion muy estable en Godot 4.x.

Evitar si puedes:
- `OBJ`: pierde parte de materiales/jerarquia.
- `FBX`: mas friccion y conversiones.

## Estructura

- `main.tscn`: escena VR base (OpenXR).
- `main.gd`: carga y distribuye modelos en cuadricula.
- `models/`: carpeta de modelos (`.glb`/`.gltf`).
- `assets/sky/`: texturas de cielo y atribucion de fuente.

## Uso

1. Copia tus exportaciones de BlockBench en `res://models`.
2. Abre el proyecto en Godot 4.6.2.
3. Ejecuta la escena principal.
4. El script carga todos los `.glb`/`.gltf`/`.fbx` de `models` (incluyendo subcarpetas) y los coloca en una cuadrícula.
5. Si necesitas ajustes por modelo, edita `models/models.yaml`.
6. Si existe una escena asociada `mismo_nombre.tscn`, se cargara en lugar del `.glb/.gltf/.fbx`.

## Parametros de la galeria

En el nodo raiz `Main` (script `main.gd`):
- `models_dir`: carpeta de modelos (por defecto `res://models`).
- `model_overrides_file`: YAML con overrides por modelo.
- `columns`: columnas de la cuadricula.
- `spacing_x`, `spacing_z`: separacion entre objetos.
- `gltf_model_scale`, `fbx_model_scale`: escala base por formato.
- `default_target_model_height`: altura usada por `fit_height` si el YAML no define otra.
- `gallery_origin`: origen de la cuadricula.
- `floor_size`: tamano del suelo en metros, por defecto `20 x 20`. Se puede sobrescribir en `models/models.yaml`.
- `xr_render_target_size_multiplier`: escala de resolucion XR en Pico/OpenXR.
- `start_in_ar`: arranque en passthrough/AR por defecto si esta soportado. Se puede sobrescribir con `default_ar` en `models/models.yaml`.
- `disable_ar`: bloquea el modo AR aunque `default_ar` o el usuario intenten activarlo.
- `sky_texture_file`: textura de cielo panoramica por defecto. Se puede sobrescribir con `texture_sky` en `models/models.yaml`.
- `illumination`: modo de iluminacion por defecto. Se puede sobrescribir con `illumination` en `models/models.yaml`.
- `ambient_light_energy`: intensidad de luz ambiente. Se puede sobrescribir en `models/models.yaml`.
- `directional_light_energy`: potencia de la luz direccional. En modo noche simula luz de luna alta.
- `xr_move_speed`, `xr_vertical_move_speed`, `xr_turn_speed_degrees`, `xr_stick_deadzone`: locomocion XR con stick izquierdo.
- `desktop_forward_move_speed`, `desktop_strafe_move_speed`, `desktop_vertical_move_speed`: velocidad de navegacion en preview Linux.

## YAML por modelo

Archivo: [`models/models.yaml`](models/models.yaml)

Convencion de override editable:
- `BancoIFU.glb` puede tener una escena asociada `BancoIFU.tscn`
- en runtime se intentara cargar `BancoIFU.tscn` antes que `BancoIFU.glb`
- el YAML sigue refiriendose siempre al archivo base, por ejemplo `BancoIFU.glb`

Ejemplo:

```yaml
default_ar: false
disable_ar: true
texture_sky: "eso_milky_way_panorama.jpg"
illumination: "night"
ambient_light_energy: 0.54
directional_light_energy: 0.24
floor_size: [80.0, 80.0]

models:
  "BancoIFU.glb":
    fit_height: false
    place_on_pedestal: false
    show_pedestal: false
    show_cookie: false
    material_mode: "matte"
    scale: 1.0
    rotation_degrees: [90.0, 0.0, 180.0]
    translation: [0.0, 1.0, 0.0]
    filtered_views:
      view1:
        button: "left_ax_button"
        group: "optics"
    controls:
      polarimeter:
        local_ctrl: "right_stick_x"
        target_node: "44V-M70-460_POLARIMETRO_ASS_ASM"
        reset_binding: "right_stick_click"
        axis: "x"
        min: -1.0
        max: 1.0
        speed: -0.10
      fm1:
        local_ctrl: "right_stick_y"
        target_node: "44V-M70-511_MOUNTANDBASE"
        reset_binding: "right_stick_click"
        axis: "z"
        min: -1.0
        max: 1.0
        speed: -0.10

  "tioazul.gltf":
    fit_height: true
    fit_width: true
    fit_depth: true
    place_on_pedestal: true
    show_pedestal: true
    show_cookie: false
    target_height: 1.5
    target_width: 1.5
    target_depth: 1.5
    rotation_degrees: [0.0, 0.0, 0.0]
    translation: [0.0, 0.0, 0.0]
```

Claves soportadas:
- `default_ar`: clave global, fuera de `models`; `true` arranca en AR y `false` arranca en VR.
- `disable_ar`: clave global, fuera de `models`; si es `true`, fuerza VR y bloquea el cambio manual a AR.
- `texture_sky`: clave global, fuera de `models`; imagen panoramica para el cielo. Un nombre simple como `"cielo.jpg"` se busca en `res://assets/sky/`; tambien acepta `assets/sky/cielo.jpg` o `res://assets/sky/cielo.jpg`.
- `illumination`: clave global, fuera de `models`; valores soportados: `"day"` mantiene la luz direccional de la escena, `"night"` usa una luz direccional alta y suave tipo luna llena, mas luz ambiente azul tenue.
- `ambient_light_energy`: clave global, fuera de `models`; intensidad no negativa de la luz ambiente.
- `directional_light_energy`: clave global, fuera de `models`; intensidad no negativa de la luz direccional.
- `floor_size`: clave global, fuera de `models`; tamano del suelo como `[ancho, fondo]`. Tambien acepta un unico numero para suelo cuadrado.
- `fit_height`: aplica o no `_fit_model_height`.
- `fit_width`: limita o no la anchura final del modelo.
- `fit_depth`: limita o no la profundidad final del modelo.
- `place_on_pedestal`: recoloca el modelo para que apoye sobre la peana.
- `show_pedestal`: muestra u oculta la peana.
- `show_cookie`: muestra u oculta la galleta de depuracion.
- `debug_control_visuals`: activa chivatos visuales de depuracion para controles y reset.
- `material_mode`: `original`, `matte` o `unshaded`.
- `target_height`: altura objetivo en metros.
- `target_width`: anchura objetivo en metros.
- `target_depth`: profundidad objetivo en metros.
- `scale`: escala final fija para ese archivo.
- `rotation_degrees`: correccion Euler en grados `[x, y, z]`.
- `translation`: desplazamiento local `[x, y, z]`.
- `filtered_views`: vistas filtradas por grupo Godot, activables por boton.
- `controls`: mapa de acciones de movimiento sobre subarboles.

Restricciones actuales de `texture_sky`:
- debe ser una panoramica equirectangular 360 grados en proporcion `2:1`
- formatos recomendados: `.jpg`, `.png` o `.webp`
- ejemplo validado: `6000x3000`
- por ahora no hay parametros de mapeo por YAML; la imagen se aplica como `PanoramaSkyMaterial`

Orden de aplicacion:
- `scale`
- `translation`
- `rotation_degrees`
- `fit_height`, `fit_width` y `fit_depth` si procede
- si hay varias restricciones activas, se aplica el factor mas restrictivo
- `place_on_pedestal` si esta activo

Valores soportados en `local_ctrl`:
- `left_stick_x`
- `left_stick_y`
- `left_stick_click`
- `right_stick_x`
- `right_stick_y`
- `right_stick_click`
- `left_trigger_click`
- `right_trigger_click`
- `left_ax_button`
- `right_ax_button`
- `left_secondary_x`
- `left_secondary_y`
- `left_secondary_click`
- `right_secondary_x`
- `right_secondary_y`
- `right_secondary_click`

Campos por control:
- nombre del control: identificador logico de la accion. Se usa en MQTT y no tiene por que coincidir con el control fisico local.
- `local_ctrl`: binding local opcional para teclado/mandos. Si no se define, la accion no responde a control local pero puede seguir usando MQTT y `reset_binding`.
- `target_node`: nombre exacto del nodo hijo a mover.
- `reset_binding`: boton que devuelve ese nodo a su posicion de reposo.
- `axis`: eje local a modificar (`x`, `y` o `z`).
- `min`: desplazamiento minimo relativo a la posicion inicial del nodo.
- `max`: desplazamiento maximo relativo a la posicion inicial del nodo.
- `speed`: velocidad en metros por segundo a entrada maxima del stick.
- `round_decimals`: resolucion decimal usada para redondear comandos absolutos e incrementales MQTT, y tambien las respuestas JSON en posicion absoluta. Por defecto `4`.
- `step`: tamano de paso opcional en unidades absolutas. Si no se define, toma por defecto el paso coherente con `round_decimals` y habilita el topic `stp`.

Campos por `filtered_views`:
- `button`: boton que conmuta esa vista filtrada. Por defecto `left_ax_button`.
- `group`: grupo Godot que debe permanecer visible cuando la vista esta activa.
- `start_active`: si arranca ya en modo filtrado.

## MQTT

Archivo local de credenciales: [`models/mqtt.yaml`](models/mqtt.yaml). Este archivo esta ignorado por git. Usa [`models/mqtt.yaml.example`](models/mqtt.yaml.example) como plantilla:

```yaml
mqtt:
  enabled: true
  host: "big.cosmobots.eu"
  port: 1883
  username: "user"
  password: "change-me"
  client_id: "vr_object_gallery"
  topic_prefix: "gallery"
  keepalive_seconds: 30
```

Para activar MQTT en un modelo, define `mqtt_id` en el modelo y `mqtt: true` en cada accion:

```yaml
models:
  "BancoIFU.glb":
    mqtt_id: "banco_ifu"
    filtered_views:
      view1:
        button: "left_ax_button"
        group: "optics"
        mqtt: true
    controls:
      polarimeter:
        local_ctrl: "right_stick_x"
        target_node: "44V-M70-460_POLARIMETRO_ASS_ASM"
        reset_binding: "right_stick_click"
        axis: "x"
        min: -1.0
        max: 1.0
        round_decimals: 4
        step: 0.0001
        speed: -0.10
        mqtt: true
```

Topics:
- filtros: `<prefix>/<mqtt_id>/<accion>` con payload booleano (`true` activa, `false` desactiva).
- movimiento normalizado: `<prefix>/<mqtt_id>/<accion>/norm` con payload numerico entre `-1` y `1`; `0` es reposo, `-1` es `min` y `1` es `max`. No se discretiza a partir de `round_decimals`.
- movimiento absoluto: `<prefix>/<mqtt_id>/<accion>/abs` con payload numerico en coordenada local absoluta del eje configurado.
- incremento absoluto: `<prefix>/<mqtt_id>/<accion>/incr` con payload numerico en las mismas unidades que `abs`; se suma a la posicion actual y luego se valida como un `abs`.
- incremento por pasos: `<prefix>/<mqtt_id>/<accion>/stp` con payload entero positivo o negativo, sin decimales. Cada paso usa `step` como incremento absoluto.
- estado: `<prefix>/<mqtt_id>/<accion>/state` publica JSON. En controles de movimiento incluye `r` (resultado), `p` (posicion absoluta actual), `n` (posicion normalizada actual, mostrada con 4 decimales) y, en `outofrange`, tambien `v` con el rango absoluto valido `[min_abs, max_abs]`.

## Nota VR

Para exportar a Android (Pico/Quest/Vive XR Elite), reutiliza el flujo de SDK/JDK ya validado en el otro proyecto:
- SDK: `/home/txinto/Android/Sdk`
- JDK: `/opt/android-studio/jbr`
- referencia oficial de Godot para export Android: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html

Requisitos adicionales para exportar y desplegar por USB:
- `adb` instalado desde Android Platform Tools y accesible en `PATH`
- modo desarrollador y depuracion USB activados en el visor
- aceptar la huella RSA del equipo cuando el visor la pida

Si ya instalaste `SDK Platform-Tools` desde Android Studio, normalmente `adb` queda en:
- `/home/txinto/Android/Sdk/platform-tools/adb`

Para exponerlo en `PATH` en `bash`, anade esto a `~/.bashrc`:

```bash
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export PATH="$ANDROID_SDK_ROOT/platform-tools:$PATH"
```

Despues recarga la shell:

```bash
source ~/.bashrc
```

Comprobacion rapida:
- `adb version`
- `adb devices`
- `ls "$HOME/Android/Sdk/platform-tools/adb"`

Si `adb` no existe en tu sistema:
- Debian/Ubuntu: instala `android-sdk-platform-tools`
- o bien instala Android Platform Tools manualmente y anade su carpeta a `PATH`

Locomocion XR actual:
- stick izquierdo horizontal: gira la camara/origen a izquierda y derecha
- stick izquierdo vertical: avanza y retrocede
- manteniendo `grip_click` izquierdo: el stick izquierdo horizontal desplaza lateralmente y el vertical sube/baja
- click del stick izquierdo (`left_stick_click`): resetea la altura al nivel inicial
- stick derecho: reservado para controles de subarboles definidos en `models.yaml`
- `Y` izquierdo (`left_by_button`): alterna entre AR y VR
- si `disable_ar: true`, el cambio manual a AR queda bloqueado
- en AR desaparece el suelo, pero no las peanas

Presets Android disponibles:
- `VR_ObjectGallery`: Pico, usa el loader OpenXR Pico.
- `Meta Quest 3`: Quest 3, usa el loader OpenXR Meta.
- `HTC Vive XR Elite`: Vive XR Elite, usa el loader OpenXR Khronos.

Despliegue USB por visor:
- Pico: `./deploy_pico.sh`
- Meta Quest: `./deploy_meta.sh`
- HTC Vive XR Elite: `./deploy_vive.sh`
- Build limpio + despliegue debug, por defecto Vive: `./clean_build_deploy.sh`

## Preview en Linux

Si OpenXR no esta activo, la escena arranca en modo escritorio con una camara normal.

Controles:
- `Click izquierdo`: capturar raton
- `Esc` o `click derecho`: liberar raton
- `W/A/S/D`: mover
- `Q/E`, `F/R` o `PageDown/PageUp`: bajar/subir
- mover raton: mirar

Simulacion de sticks en Linux:
- `J/L`: `left_stick_x`
- `K/I`: `left_stick_y`
- flechas `izquierda/derecha`: `right_stick_x`
- flechas `abajo/arriba`: `right_stick_y`
- `U`: `left_stick_click`
- `O`: `right_stick_click`
- `B`: `left_by_button`
- `N`: `right_by_button`
- `Y`: `left_trigger_click`
- `P`: `right_trigger_click`
- `1`: `left_ax_button`
- `2`: `right_ax_button`
- `F/H`: `left_secondary_x`
- `G/T`: `left_secondary_y`
- `7`: `left_secondary_click`
- keypad `4/6`: `right_secondary_x`
- keypad `2/8`: `right_secondary_y`
- `0`: `right_secondary_click`

Feedback visual de varitas:
- solo se iluminan en blanco con el gatillo del controlador correspondiente
- en Linux: `Y` para la izquierda y `P` para la derecha

## Despliegue Pico

Usa `./deploy_pico.sh` para verificar que el APK es mas reciente que el ultimo cambio fuente, reinstalar y lanzar la app en las Pico.

Prerequisitos:
- `adb` disponible en `PATH`
- visor visible en `adb devices` con estado `device`

## Despliegue Meta Quest 3

- preset de exportacion Android: `Meta Quest 3`
- APK esperado: `./VR_ObjectGallery_MetaQuest3.apk`
- despliegue: `./deploy_meta.sh`
- mismos prerequisitos de `adb` y depuracion USB que en Pico

## Export Web

- preset de exportacion: `Web`
- salida esperada: `./web/index.html`
- exportacion por terminal: `./export_web.sh`
- servidor local de prueba: `./serve_web.sh` y abrir `http://localhost:8000`

El export Web genera los ficheros `.html`, `.js`, `.wasm` y `.pck` en `web/`. Si se quiere integrar en React, exporta el mismo preset directamente a una carpeta tipo `public/simulator/index.html`.

Notas:
- En navegador se usa el modo preview de escritorio, no OpenXR nativo.
- El preset Web excluye `models/mqtt.yaml`, `addons/godotopenxrvendors/`, `web/` y `backup/` para no publicar credenciales, loaders nativos ni artefactos de exportacion dentro del `.pck`.
- El export Web debe servirse desde HTTP/HTTPS; abrir el HTML con `file://` puede fallar al cargar WASM/PCK.
- Si se activa `Use Threads` en el preset Web, el servidor debe enviar `Cross-Origin-Opener-Policy: same-origin` y `Cross-Origin-Embedder-Policy: require-corp`.
