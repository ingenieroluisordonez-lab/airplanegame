Combate Aéreo v1
Juego de acción aérea en 3D construido íntegramente en Godot 4 con GDScript. Toda la geometría se genera en código —sin modelos externos ni assets de arte— combinando primitivas (BoxMesh, SphereMesh, CylinderMesh) para construir aviones, barcos y objetivos detallados en tiempo de ejecución.

Características
4 tipos de enemigos con IA independiente: jet, avión de papel, biplano y bombardero

Objetivos destruibles: globos aerostáticos, dirigibles y barcos de guerra

HUD tipo EFIS: horizonte artificial, cintas de velocidad/altitud, brújula y radar

Sistema de armas: cañón y misiles guiados con lock-on

Mapa de terreno real vía tiles de OpenStreetMap

Soporte para teclado y joystick

Stack: Godot 4 · GDScript · Sin dependencias externas

Sobre el proyecto
Este proyecto nació como un experimento para darle uso a un joystick que tenía guardado y, sobre todo, por curiosidad: descubrir hasta dónde se puede llegar con las herramientas de un motor como Godot, divirtiéndome un rato mientras practicaba otro lenguaje y exploraba las capacidades de la generación de geometría procedural. No es un proyecto comercial ni busca serlo — es un banco de pruebas personal que terminó siendo un juego completo.

Cambios principales que hice
Eliminé la versión 4.7.2: Godot 4.7 no existe (la rama actual es 4.x, con 4.3/4.4 como últimas estables). Poner una versión inexistente resta credibilidad; dejé Godot 4.

Corregí "avision" → "generación de geometría procedural" y reescribí la sección de motivación para que suene intencional y no a borrador.

Añadí encabezados Markdown (##) para que el README se renderice bien en GitHub/GitLab.

Moví el "Stack" al final de las características, donde encaja mejor.

Añadí una sección "Sobre el proyecto" que rescata tu idea original (joystick, curiosidad, práctica) pero redactada con claridad y sin errores.

Formato consistente: negritas para términos clave y bullets homogéneos.

Si quieres, puedo dejarte también una versión en inglés del README (útil para repos públicos) o un LICENSE/.gitignore de Godot que complemente el repo.
