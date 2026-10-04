import 'dart:convert';
import 'dart:typed_data';

/// QuickShare transfer protocol v2 framing, shared by every transport (LAN, internet,
/// Bluetooth). A frame is one message on the underlying channel:
///
///     [type: u8][body...]
///
/// Control frames carry a UTF-8 JSON body. Data frames ([FrameType.chunk]) are binary:
///
///     [0x10][tag: u32][file index: u16][sequence: u32][data...]
///
/// `tag` identifies one transfer (random per offer), so stale chunks of a cancelled transfer
/// can never be mistaken for a new one. `sequence` is the chunk number within the file; the
/// receiver rejects anything out of order.
enum FrameType {
  /// Receiver -> sender on connect: {nonce, name, id, platform, v}.
  challenge(0x01),

  /// Sender -> receiver: {name, id, platform, mode, proof, v}.
  hello(0x02),

  /// Receiver -> sender after a valid hello: {resumeId}.
  welcome(0x03),

  /// Either side: the handshake failed ({reason}); the channel closes.
  reject(0x04),

  /// {transferId, tag, files: [{name, size}], total, chunkSize, sender: {...}, resume}
  offer(0x05),

  /// {tag, resumeFile, resumeOffset}
  accept(0x06),

  /// {tag, reason}
  decline(0x07),

  /// {tag, file, offset}
  fileStart(0x08),

  /// {tag, file, size, sha256}
  fileEnd(0x09),

  /// {tag, file, ok, error}
  fileResult(0x0A),

  /// Flow control from the receiver: {tag, received} (total bytes written so far).
  ack(0x0B),

  /// Either side: {tag, reason}.
  cancel(0x0C),

  /// Graceful goodbye: {reason}.
  bye(0x0D),

  chunk(0x10);

  const FrameType(this.code);
  final int code;

  static FrameType? fromCode(int code) {
    for (final t in values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

class ProtocolException implements Exception {
  ProtocolException(this.message);
  final String message;
  @override
  String toString() => 'ProtocolException: $message';
}

/// A decoded frame.
class Frame {
  Frame.control(this.type, this.json)
      : tag = 0,
        fileIndex = 0,
        sequence = 0,
        data = null;

  Frame.chunk({required this.tag, required this.fileIndex, required this.sequence, required Uint8List this.data})
      : type = FrameType.chunk,
        json = const {};

  final FrameType type;
  final Map<String, dynamic> json;
  final int tag;
  final int fileIndex;
  final int sequence;
  final Uint8List? data;

  static const int chunkHeaderLength = 11;

  static Uint8List encodeControl(FrameType type, Map<String, dynamic> body) {
    assert(type != FrameType.chunk);
    final payload = utf8.encode(jsonEncode(body));
    final out = Uint8List(payload.length + 1);
    out[0] = type.code;
    out.setRange(1, out.length, payload);
    return out;
  }

  static Uint8List encodeChunk({required int tag, required int fileIndex, required int sequence, required List<int> data}) {
    final out = Uint8List(chunkHeaderLength + data.length);
    final view = ByteData.sublistView(out);
    out[0] = FrameType.chunk.code;
    view.setUint32(1, tag);
    view.setUint16(5, fileIndex);
    view.setUint32(7, sequence);
    out.setRange(chunkHeaderLength, out.length, data);
    return out;
  }

  static Frame decode(Uint8List bytes) {
    if (bytes.isEmpty) throw ProtocolException('empty frame');
    final type = FrameType.fromCode(bytes[0]);
    if (type == null) throw ProtocolException('unknown frame type ${bytes[0]}');
    if (type == FrameType.chunk) {
      if (bytes.length < chunkHeaderLength) throw ProtocolException('short chunk');
      final view = ByteData.sublistView(bytes);
      return Frame.chunk(
        tag: view.getUint32(1),
        fileIndex: view.getUint16(5),
        sequence: view.getUint32(7),
        data: Uint8List.sublistView(bytes, chunkHeaderLength),
      );
    }
    try {
      final decoded = jsonDecode(utf8.decode(Uint8List.sublistView(bytes, 1)));
      if (decoded is! Map<String, dynamic>) throw ProtocolException('control body is not an object');
      return Frame.control(type, decoded);
    } on FormatException {
      throw ProtocolException('malformed ${type.name} frame');
    }
  }
}
