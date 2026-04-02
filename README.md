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

## Uso

1. Copia tus exportaciones de BlockBench en `res://models`.
2. Abre el proyecto en Godot 4.6.2.
3. Ejecuta la escena principal.
4. El script carga todos los `.glb`/`.gltf`/`.fbx` de `models` (incluyendo subcarpetas) y los coloca en una cuadrícula.
5. Si necesitas ajustes por modelo, edita `models/models.yaml`.

## Parametros de la galeria

En el nodo raiz `Main` (script `main.gd`):
- `models_dir`: carpeta de modelos (por defecto `res://models`).
- `model_overrides_file`: YAML con overrides por modelo.
- `columns`: columnas de la cuadricula.
- `spacing_x`, `spacing_z`: separacion entre objetos.
- `gltf_model_scale`, `fbx_model_scale`: escala base por formato.
- `default_target_model_height`: altura usada por `fit_height` si el YAML no define otra.
- `gallery_origin`: origen de la cuadricula.

## YAML por modelo

Archivo: [`models/models.yaml`](models/models.yaml)

Ejemplo:

```yaml
models:
  "44V-M70-001_LAYOUT_IFU_BENCH2.glb":
    fit_height: false
    place_on_pedestal: false
    scale: 1.0
    rotation_degrees: [0.0, 0.0, 90.0]
    translation: [0.0, 1.0, 0.0]

  "tioazul.gltf":
    fit_height: true
    place_on_pedestal: true
    target_height: 1.5
    rotation_degrees: [0.0, 0.0, 0.0]
    translation: [0.0, 0.0, 0.0]
```

Claves soportadas:
- `fit_height`: aplica o no `_fit_model_height`.
- `place_on_pedestal`: recoloca el modelo para que apoye sobre la peana.
- `target_height`: altura objetivo en metros.
- `scale`: escala final fija para ese archivo.
- `rotation_degrees`: correccion Euler en grados `[x, y, z]`.
- `translation`: desplazamiento local `[x, y, z]`.

Orden de aplicacion:
- `scale`
- `translation`
- `rotation_degrees`
- `fit_height` si procede
- `place_on_pedestal` si esta activo

## Nota VR

Para exportar a Android (Pico/Quest), reutiliza el flujo de SDK/JDK ya validado en el otro proyecto:
- SDK: `/home/txinto/Android/Sdk`
- JDK: `/opt/android-studio/jbr`

## Preview en Linux

Si OpenXR no esta activo, la escena arranca en modo escritorio con una camara normal.

Controles:
- `Click izquierdo`: capturar raton
- `Esc` o `click derecho`: liberar raton
- `W/A/S/D`: mover
- `Q/E`: bajar/subir
- mover raton: mirar
