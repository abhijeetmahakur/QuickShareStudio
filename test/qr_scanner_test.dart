import 'package:flutter_test/flutter_test.dart';
import 'package:quickshare/features/connect/qr_scanner_page.dart';

void main() {
  group('PairingQr Parsing and Validation Tests', () {
    test('Parses valid quickshare://pair QR payload with all parameters', () {
      const raw =
          'quickshare://pair?code=543210&n=nonce_abc123&sid=sess_456&host=192.168.1.50&port=8088&name=MyPhone';
      final qr = PairingQr.parse(raw);

      expect(qr, isNotNull);
      expect(qr!.code, '543210');
      expect(qr.nonce, 'nonce_abc123');
      expect(qr.host, '192.168.1.50');
      expect(qr.port, 8088);
    });

    test('Parses bare 6-digit numeric code as valid PairingQr', () {
      const raw = '123456';
      final qr = PairingQr.parse(raw);

      expect(qr, isNotNull);
      expect(qr!.code, '123456');
      expect(qr.nonce, isNull);
      expect(qr.host, isNull);
      expect(qr.port, isNull);
    });

    test('Parses query string without quickshare scheme', () {
      const raw = 'code=987654&host=10.0.0.5&port=9000';
      final qr = PairingQr.parse(raw);

      expect(qr, isNotNull);
      expect(qr!.code, '987654');
      expect(qr.host, '10.0.0.5');
      expect(qr.port, 9000);
    });

    test('Rejects invalid QR codes (arbitrary URLs or non-QuickShare strings)', () {
      expect(PairingQr.parse('https://example.com/login'), isNull);
      expect(PairingQr.parse('WIFI:S:MyWifi;T:WPA;P:password;;'), isNull);
      expect(PairingQr.parse('random_text_12345'), isNull);
      expect(PairingQr.parse(''), isNull);
      expect(PairingQr.parse('   '), isNull);
      expect(PairingQr.parse('quickshare://pair?code=123'), isNull); // only 3 digits
      expect(PairingQr.parse('quickshare://pair?code=abcdef'), isNull); // non-digits
    });
  });
}
