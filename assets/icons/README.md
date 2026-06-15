Coloca aquí los assets para el icono adaptable de Android.

Recomendación para una buena apariencia centrada:

- icon_fg.png (foreground)
  - Tamaño: 432x432 px (Android recomienda este lienzo para adaptive icons)
  - Fondo transparente
  - El logotipo debe ocupar ~66–72% del ancho/alto (deja margen "safe zone")
  - Centrado perfectamente, sin sombras exteriores pegadas al borde

- icon_bg.png (opcional si no usas color)
  - Tamaño: 432x432 px
  - Color plano o patrón sutil de marca

- icon_mono.png (opcional, Android 13+)
  - Versión monocroma del logotipo (blanco sobre transparente)

Pasos para generar:

1) Exporta tus PNG a esta carpeta con los nombres indicados.
2) Ejecuta:
   flutter pub get
   flutter pub run flutter_launcher_icons

Esto creará los mipmap y el XML de adaptive icon para que el logo se adapte a la máscara del dispositivo y quede centrado.

