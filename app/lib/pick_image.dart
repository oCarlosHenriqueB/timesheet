import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'models.dart';

/// Imagens acima disso são reduzidas (até 1920 px de largura, JPEG) antes do envio. A API aceita até 3 MB.
const _shrinkAbove = 1500 * 1024;
const _maxWidth = 1920;

/// Abre o seletor de arquivos do navegador para escolher prints.
Future<List<PickedImage>> pickImages() {
  final done = Completer<List<PickedImage>>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/png,image/jpeg,image/gif,image/webp'
    ..multiple = true;
  // Callbacks passados ao navegador não podem ser async: disparam a leitura e retornam.
  input.onchange = ((web.Event _) {
    done.complete(_readAll(input.files));
  }).toJS;
  input.addEventListener('cancel', ((web.Event _) => done.complete([])).toJS);
  input.click();
  return done.future;
}

/// Escuta Ctrl+V / Cmd+V na página e entrega os prints colados. Chame o retorno para parar de escutar.
void Function() listenPastedImages(void Function(List<PickedImage>) onImages) {
  final listener = ((web.ClipboardEvent e) {
    final items = e.clipboardData?.items;
    if (items == null) return;
    final files = <web.File>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.kind == 'file' && item.type.startsWith('image/')) {
        final file = item.getAsFile();
        if (file != null) files.add(file);
      }
    }
    if (files.isNotEmpty) Future.wait(files.map(_read)).then(onImages);
  }).toJS;
  web.document.addEventListener('paste', listener);
  return () => web.document.removeEventListener('paste', listener);
}

/// Navegador e tamanho da janela, para ajudar a reproduzir erros.
String deviceInfo() {
  final w = web.window;
  return '${w.navigator.userAgent} · janela ${w.innerWidth}x${w.innerHeight}';
}

Future<List<PickedImage>> _readAll(web.FileList? list) async {
  if (list == null) return [];
  return [for (var i = 0; i < list.length; i++) await _read(list.item(i)!)];
}

Future<PickedImage> _read(web.File file) async {
  final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
  if (bytes.length <= _shrinkAbove) return PickedImage(file.type, bytes);
  return _shrink(file);
}

/// Redesenha a imagem num canvas menor e gera um JPEG.
Future<PickedImage> _shrink(web.File file) async {
  final bitmap = await web.window.createImageBitmap(file).toDart;
  final scale = min(1.0, _maxWidth / bitmap.width);
  final canvas = web.HTMLCanvasElement()
    ..width = (bitmap.width * scale).round()
    ..height = (bitmap.height * scale).round();
  (canvas.getContext('2d') as web.CanvasRenderingContext2D)
      .drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  final blob = Completer<web.Blob?>();
  canvas.toBlob(((web.Blob? b) => blob.complete(b)).toJS, 'image/jpeg', 0.85.toJS);
  final result = await blob.future;
  if (result == null) throw StateError('Não foi possível reduzir a imagem.');
  final bytes = (await result.arrayBuffer().toDart).toDart.asUint8List();
  return PickedImage('image/jpeg', Uint8List.fromList(bytes));
}
