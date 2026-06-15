import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) async {
  // Defaults
  final foregroundScale = _readDoubleArg(args, '--fg-scale') ?? 0.70; // 70% of canvas
  final legacyScale = _readDoubleArg(args, '--legacy-scale') ?? 0.78; // 78% of canvas
  final bgHex = _readStringArg(args, '--bg') ?? '#FFFFFF';

  final inputPath = 'assets/icons/icon_fg.png';
  final outFgPadded = 'assets/icons/icon_fg_padded.png';
  final outBg = 'assets/icons/icon_bg.png';
  final outLegacy = 'assets/icons/icon_legacy.png';

  _ensureExists(inputPath);

  // Load input logo
  final inputBytes = await File(inputPath).readAsBytes();
  final input = img.decodeImage(inputBytes);
  if (input == null) {
    stderr.writeln('No se pudo decodificar $inputPath');
    exit(1);
  }

  // Create adaptive foreground 432x432 with transparent background
  final fgCanvasSize = 432;
  final fgCanvas = img.Image(width: fgCanvasSize, height: fgCanvasSize);
  // Transparent background
  img.fill(fgCanvas, color: img.ColorRgba8(0, 0, 0, 0));

  final fgTargetSize = (fgCanvasSize * foregroundScale).round();
  final resizedFg = _fitWithin(input, fgTargetSize, fgTargetSize);
  final fgX = ((fgCanvasSize - resizedFg.width) / 2).round();
  final fgY = ((fgCanvasSize - resizedFg.height) / 2).round();
  img.compositeImage(fgCanvas, resizedFg, dstX: fgX, dstY: fgY);
  await File(outFgPadded).writeAsBytes(img.encodePng(fgCanvas));

  // Create background 432x432 solid color
  final bgColor = _parseHexColor(bgHex);
  final bgCanvas = img.Image(width: fgCanvasSize, height: fgCanvasSize);
  img.fill(bgCanvas, color: bgColor);
  await File(outBg).writeAsBytes(img.encodePng(bgCanvas));

  // Create legacy 512x512 with same background color and centered logo
  final legacySize = 512;
  final legacyCanvas = img.Image(width: legacySize, height: legacySize);
  img.fill(legacyCanvas, color: bgColor);
  final legacyTarget = (legacySize * legacyScale).round();
  final resizedLegacy = _fitWithin(input, legacyTarget, legacyTarget);
  final lx = ((legacySize - resizedLegacy.width) / 2).round();
  final ly = ((legacySize - resizedLegacy.height) / 2).round();
  img.compositeImage(legacyCanvas, resizedLegacy, dstX: lx, dstY: ly);
  await File(outLegacy).writeAsBytes(img.encodePng(legacyCanvas));

  stdout.writeln('Generados:');
  stdout.writeln('  - $outFgPadded');
  stdout.writeln('  - $outBg');
  stdout.writeln('  - $outLegacy');
  stdout.writeln('Siguiente:');
  stdout.writeln('  dart run flutter_launcher_icons');
}

img.Image _fitWithin(img.Image source, int maxW, int maxH) {
  final scale = _min(maxW / source.width, maxH / source.height);
  final w = (source.width * scale).round();
  final h = (source.height * scale).round();
  return img.copyResize(source, width: w, height: h, interpolation: img.Interpolation.cubic);
}

double _min(double a, double b) => a < b ? a : b;

img.Color _parseHexColor(String hex) {
  var v = hex.trim();
  if (v.startsWith('#')) v = v.substring(1);
  if (v.length == 6) v = 'FF$v';
  if (v.length != 8) {
    throw ArgumentError('Color inválido: $hex');
  }
  final a = int.parse(v.substring(0, 2), radix: 16);
  final r = int.parse(v.substring(2, 4), radix: 16);
  final g = int.parse(v.substring(4, 6), radix: 16);
  final b = int.parse(v.substring(6, 8), radix: 16);
  return img.ColorRgba8(r, g, b, a);
}

double? _readDoubleArg(List<String> args, String key) {
  final i = args.indexOf(key);
  if (i >= 0 && i + 1 < args.length) {
    return double.tryParse(args[i + 1]);
  }
  return null;
}

String? _readStringArg(List<String> args, String key) {
  final i = args.indexOf(key);
  if (i >= 0 && i + 1 < args.length) {
    return args[i + 1];
  }
  return null;
}

void _ensureExists(String path) {
  if (!File(path).existsSync()) {
    stderr.writeln('No existe el archivo requerido: $path');
    exit(1);
  }
}
