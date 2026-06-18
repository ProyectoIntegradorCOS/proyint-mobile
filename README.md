# proyint-mobile

Aplicación móvil del proyecto **THAQHIRI** — app Android para colaboradores de campo de la ONP. Desarrollada en Flutter.

## Tecnologías

- **Flutter 3.44.2** → Android APK
- **Dart**
- **Mapbox Maps SDK** — navegación y geofencing
- **GitHub Actions** — CI/CD con publicación en S3

## Funcionalidades

- Recepción de jornada asignada (visitas del día)
- Navegación a cada destino con mapa
- Confirmación de llegada por **geofencing (radio 500 m)**
- Completar cuestionarios en campo
- Registro de resultados de visita

## Descarga del APK

El APK más reciente siempre está disponible en S3:

```
s3://thaqhiri-dev-apk-023894313590/thaqhiri-latest.apk
```

También se publica con versión semántica:

```
s3://thaqhiri-dev-apk-023894313590/thaqhiri-0.1.<build>.apk
```

## Ejecución local

```bash
flutter pub get
flutter run
```

Requiere un emulador Android o dispositivo físico conectado.

## CI/CD

El pipeline `.github/workflows/deploy.yml` ejecuta:

1. **Setup** Flutter 3.44.2
2. **Build** APK: `flutter build apk --release`
3. **Upload** a S3: versión semántica + `thaqhiri-latest.apk`

El token de Mapbox y la URL del backend se inyectan como variables de entorno en tiempo de CI.
