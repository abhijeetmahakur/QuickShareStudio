
import 'dart:js_interop';


@JS('window.__quickshareOnPasteImage')
external set _onPasteImage(JSFunction? value);

/// Registers [handler] to receive images from the browser's native paste event
/// (a data URL, or null when the clipboard held no image). Pass null to unregister.
void setWebPasteImageHandler(void Function(String? dataUrl)? handler) {
  try {
    _onPasteImage = handler == null
        ? null
        : ((JSString? dataUrl) {
            handler(dataUrl?.toDart);
          }).toJS;
  } catch (_) {}
}

@JS('window.quicksharePopDroppedImages')
external JSString _jsPopDroppedImages();

String? popWebDroppedImagesJson() {
  try {
    final str = _jsPopDroppedImages().toDart;
    if (str.isNotEmpty && str != '[]') {
      return str;
    }
  } catch (_) {}
  return null;
}

@JS('window.quickshareReadClipboardImageAsync')
external JSPromise<JSString?> _jsReadClipboardImageAsync();

Future<String?> readWebClipboardImageAsync() async {
  try {
    final promise = _jsReadClipboardImageAsync();
    final jsStr = await promise.toDart;
    return jsStr?.toDart;
  } catch (_) {
    return null;
  }
}
