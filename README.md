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
2. Abre el proyecto en Godot 4.6.1.
3. Ejecuta la escena principal.
4. El script carga todos los `.glb`/`.gltf` de `models` (incluyendo subcarpetas) y los coloca en una cuadrícula.

## Parametros de la galeria

En el nodo raiz `Main` (script `main.gd`):
- `models_dir`: carpeta de modelos (por defecto `res://models`).
- `columns`: columnas de la cuadricula.
- `spacing_x`, `spacing_z`: separacion entre objetos.
- `model_scale`: escala global aplicada a cada modelo.
- `gallery_origin`: origen de la cuadricula.

## Nota VR

Para exportar a Android (Pico/Quest), reutiliza el flujo de SDK/JDK ya validado en el otro proyecto:
- SDK: `/home/txinto/Android/Sdk`
- JDK: `/opt/android-studio/jbr`

